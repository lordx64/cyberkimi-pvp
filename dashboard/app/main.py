"""CyberPVP dashboard — reads published trace bundles, serves results + live view.

Only reads from TRACES_DIR (curated, checksummed bundles). It never touches the
CyberGym judge server, agent containers, or any credential.
"""
import asyncio
import json
import os
from pathlib import Path

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, PlainTextResponse
from fastapi.staticfiles import StaticFiles

TRACES_DIR = Path(os.environ.get("TRACES_DIR", "/data/cyberpvp/traces"))
SIDES = ("kimi", "altar")

app = FastAPI(title="cyberpvp")


def _runs() -> list[dict]:
    out = []
    if not TRACES_DIR.is_dir():
        return out
    for d in sorted(TRACES_DIR.iterdir(), reverse=True):
        m = d / "manifest.json"
        if not m.is_file():
            continue
        try:
            manifest = json.loads(m.read_text())
        except json.JSONDecodeError:
            continue
        out.append({
            "run_id": manifest.get("run_id", d.name),
            "started_at": manifest.get("started_at"),
            "status": manifest.get("status", "unknown"),
            "n_tasks": len(manifest.get("task_ids", [])),
            "sides": {s: (manifest.get("sides", {}).get(s, {}).get("model"))
                      for s in SIDES},
            "results": manifest.get("results"),
        })
    return out


def _run_dir(run_id: str) -> Path:
    # run ids may not escape the traces dir
    if "/" in run_id or ".." in run_id:
        raise HTTPException(400, "bad run id")
    d = TRACES_DIR / run_id
    if not d.is_dir():
        raise HTTPException(404, "no such run")
    return d


@app.get("/healthz")
def healthz():
    return {"ok": True}

from fastapi.responses import RedirectResponse


@app.get("/research-view")
def research_view():
    return RedirectResponse("/graphs.html", status_code=308)


@app.get("/", include_in_schema=False)
def root():
    # land directly on the research view; the live arena lives at /index.html
    return RedirectResponse("/graphs.html", status_code=308)


@app.get("/api/runs")
def list_runs():
    return _runs()


@app.get("/api/runs/{run_id}/manifest")
def manifest(run_id: str):
    m = _run_dir(run_id) / "manifest.json"
    if not m.is_file():
        raise HTTPException(404, "no manifest")
    return FileResponse(m)


@app.get("/api/runs/{run_id}/checksums")
def checksums(run_id: str):
    c = _run_dir(run_id) / "checksums.txt"
    if not c.is_file():
        raise HTTPException(404, "no checksums")
    return PlainTextResponse(c.read_text())


@app.get("/api/runs/{run_id}/events/{side}")
def events(run_id: str, side: str):
    if side not in SIDES:
        raise HTTPException(400, "side must be kimi|altar")
    f = _run_dir(run_id) / "events" / f"{side}.events.jsonl"
    if not f.is_file():
        # fall back. raw listing lets viewers browse even before adapters exist
        raw = _run_dir(run_id) / "raw" / side
        if raw.is_dir():
            return {"note": "no normalized events yet",
                    "raw_files": sorted(str(p.relative_to(raw)) for p in raw.rglob("*") if p.is_file())}
        raise HTTPException(404, "no events")
    return FileResponse(f)


async def _tail(ws: WebSocket, f: Path, side: str, pos: int) -> int:
    """Send any bytes appended to f since pos; returns new pos."""
    try:
        size = f.stat().st_size
    except OSError:
        return pos
    if size <= pos:
        return pos
    with f.open("rb") as fh:
        fh.seek(pos)
        data = fh.read(size - pos)
    for line in data.splitlines():
        if line:
            await ws.send_text(json.dumps({
                "side": side, "line": line.decode("utf-8", "replace")[:4000]}))
    return size


@app.websocket("/ws/live/{run_id}")
async def live(ws: WebSocket, run_id: str):
    await ws.accept()
    try:
        d = _run_dir(run_id)
    except HTTPException:
        await ws.close(code=4404)
        return
    files = {s: d / "events" / f"{s}.events.jsonl" for s in SIDES}
    pos = {s: 0 for s in SIDES}
    try:
        while True:
            for s in SIDES:
                if files[s].is_file():
                    pos[s] = await _tail(ws, files[s], s, pos[s])
            await asyncio.sleep(1.0)
    except WebSocketDisconnect:
        pass


STATIC = Path(__file__).resolve().parent.parent / "static"
app.mount("/", StaticFiles(directory=STATIC, html=True), name="static")
