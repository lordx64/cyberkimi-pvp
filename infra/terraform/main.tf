provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "cyberpvp"
      Purpose = "cybergym-dual-model-benchmark"
    }
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "this" {
  key_name   = "cyberpvp-bench"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "aws_security_group" "bench" {
  name        = "cyberpvp-bench-sg"
  description = "cyberpvp benchmark host: dashboard only, CyberGym stays private"
  vpc_id      = data.aws_vpc.default.id

  dynamic "ingress" {
    for_each = var.ssh_cidrs
    content {
      description = "ssh"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  ingress {
    description = "http dashboard (certbot-http-challenge)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "https dashboard"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# NOTE: IAM role / instance profile intentionally omitted — the cyberkimi
# deploy user lacks iam:CreateRole, and without the role SSM Session Manager
# fallback won't work. Access is SSH-only via the key in aws_key_pair.this.
# If you want SSM Session Manager fallback, an account admin must grant
# iam:CreateRole to the cyberkimi user (or pre-create cyberpvp-bench-role),
# then re-add: aws_iam_role + AmazonSSMManagedInstanceCore + instance profile.

resource "aws_instance" "bench" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.instance_type
  key_name             = aws_key_pair.this.key_name

  vpc_security_group_ids = [aws_security_group.bench.id]
  monitoring             = false

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = var.root_volume_gb
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = file("${path.module}/bootstrap.sh")

  tags = {
    Name = "cyberpvp-bench"
  }
}

resource "aws_ebs_volume" "data" {
  availability_zone = aws_instance.bench.availability_zone
  size              = var.data_volume_gb
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "cyberpvp-bench-data"
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.bench.id
}

resource "aws_eip" "bench" {
  instance = aws_instance.bench.id
  domain   = "vpc"

  tags = {
    Name = "cyberpvp-bench-eip"
  }
}
