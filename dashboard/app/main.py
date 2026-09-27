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


_EVENTS_CACHE: dict = {}


def _events_parsed(path: Path) -> list[dict]:
    """Parsed events of an append-only JSONL file, incrementally re-read."""
    try:
        size = path.stat().st_size
    except OSError:
        return []
    key = str(path)
    pos, evs = _EVENTS_CACHE.get(key, (0, []))
    if size < pos:  # truncated or rotated: start over
        pos, evs = 0, []
    if size == pos:
        return evs
    with path.open("rb") as fh:
        fh.seek(pos)
        chunk = fh.read(size - pos)
    nl = chunk.rfind(b"\n")  # never consume a half-written final line
    if nl < 0:
        return evs
    for line in chunk[:nl].decode("utf-8", "replace").splitlines():
        if not line.strip():
            continue
        try:
            e = json.loads(line)
            e["_n"] = len(evs)  # global cursor: file offset (seq resets per task)
            evs.append(e)
        except json.JSONDecodeError:
            pass
    _EVENTS_CACHE[key] = (pos + nl + 1, evs)
    return evs


@app.get("/api/runs/{run_id}/events/{side}")
def events(run_id: str, side: str, tail: int = 0, limit: int = 0,
           before_seq: int = 0, since_seq: int = 0):
    if side not in SIDES:
        raise HTTPException(400, "side must be kimi|altar")
    f = _run_dir(run_id) / "events" / f"{side}.events.jsonl"
    if not (tail or before_seq or since_seq):
        # legacy: whole file (the dashboard figures need full history)
        if not f.is_file():
            # fall back. raw listing lets viewers browse even before adapters exist
            raw = _run_dir(run_id) / "raw" / side
            if raw.is_dir():
                return {"note": "no normalized events yet",
                        "raw_files": sorted(str(p.relative_to(raw)) for p in raw.rglob("*") if p.is_file())}
            raise HTTPException(404, "no events")
        return FileResponse(f)
    if not f.is_file():
        raise HTTPException(404, "no events")
    evs = _events_parsed(f)
    if since_seq:
        return {"events": [e for e in evs if e["_n"] > since_seq],
                "total": len(evs)}
    if before_seq:
        prev = [e for e in evs if e["_n"] < before_seq]
        lim = max(1, min(limit or 20, 200))
        return {"events": prev[-lim:], "total": len(evs),
                "has_more": len(prev) > lim}
    n = max(1, min(tail, 500))
    return {"events": evs[-n:], "total": len(evs)}


@app.get("/api/runs/{run_id}/events/{side}/stats")
def event_stats(run_id: str, side: str):
    if side not in SIDES:
        raise HTTPException(400, "side must be kimi|altar")
    f = _run_dir(run_id) / "events" / f"{side}.events.jsonl"
    if not f.is_file():
        raise HTTPException(404, "no events")
    assigned = solved = infra = failed = iters = tokens = 0
    cur = None
    cur_task_tokens = 0
    for e in _events_parsed(f):
        k = e.get("kind")
        if k == "task_assign":
            assigned += 1
            cur = e.get("task_id")
            cur_task_tokens = 0
        elif k == "llm_response":
            iters += 1
        elif k == "budget_update" and e.get("payload"):
            # cum_tokens resets per task: lane total = sum of per-task maxima
            c = e["payload"].get("cum_tokens", 0)
            tokens += max(0, c - cur_task_tokens)
            cur_task_tokens = max(cur_task_tokens, c)
        elif k == "run_end":
            sm = e.get("summary") or ""
            if sm == "SOLVED":
                solved += 1
            elif sm.startswith("infra_error"):
                infra += 1
            else:
                failed += 1
            cur = None
    return {"assigned": assigned, "solved": solved, "infra": infra,
            "failed": failed, "iters": iters, "cum_tokens": tokens,
            "current_task": cur}


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
