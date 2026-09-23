output "instance_id" {
  value = aws_instance.bench.id
}

output "public_ip" {
  description = "Elastic IP — point cyberpvp.adverserial.ai (A record) here"
  value       = aws_eip.bench.public_ip
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/cyberpvp_ed25519 ubuntu@${aws_eip.bench.public_ip}"
}

# Note: no SSM output — the instance has no IAM role (the cyberkimi deploy user
# lacks iam:CreateRole), so Session Manager will not work here. SSH is the only
# access path.

output "next_steps" {
  value = <<-EOT
    1. DNS: create A record  cyberpvp.adverserial.ai -> ${aws_eip.bench.public_ip}
    2. ssh -i ~/.ssh/cyberpvp_ed25519 ubuntu@${aws_eip.bench.public_ip}
    3. Verify bootstrap:  cat /data/cyberpvp/.bootstrap_done
    4. Copy/clone this repo onto the box, then:
         bash scripts/setup_box.sh
         bash scripts/download_data.sh --subset
  EOT
}
