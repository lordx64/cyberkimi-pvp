variable "region" {
  description = "AWS region for the benchmark box"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "CPU instance type. Needs enough cores to run many CyberGym task containers side by side. Sizing notes: account's compute-optimized vCPU quota is 16 with only ~6 vCPU free right now (btcpay-wallet-rpc t3.small ≈2 + v8ctf-x64 c7i.2xlarge ≈8 running). c7i.xlarge (4 vCPU) fits without touching anything. Upgrade paths: (a) stop v8ctf-x64 → use c7i.2xlarge (8 vCPU); (b) request quota increase → c7i.8xlarge (32)."
  type        = string
  default     = "c7i.xlarge"
}

variable "root_volume_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 60
}

variable "data_volume_gb" {
  description = "Persistent /data volume for CyberGym datasets, docker images, and traces. Subset workflow fits in a few hundred GB; this default leaves room to grow into binary-only mode (~130GB) plus agent docker images."
  type        = number
  default     = 1000
}

variable "ssh_cidrs" {
  description = "CIDRs allowed to SSH (port 22). Instance has no IAM role (Session Manager won't work), so SSH is the only access — restrict to your own /32 for production posture."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_public_key_path" {
  description = "Public key uploaded to the instance for SSH access"
  type        = string
  default     = "~/.ssh/cyberpvp_ed25519.pub"
}
