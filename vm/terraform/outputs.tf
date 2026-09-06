output "nodes" {
  description = "Node name -> public IP."
  value       = { for i in aws_instance.node : i.tags.Name => i.public_ip }
}

output "private_ips" {
  description = "Node name -> private IP (what the nodes use to reach each other)."
  value       = { for i in aws_instance.node : i.tags.Name => i.private_ip }
}

output "pem" {
  description = "Path to the generated private key."
  value       = local_sensitive_file.pem.filename
}

output "ami" {
  description = "AMI the nodes were stamped from."
  value       = "${data.aws_ami.devstation.id} (${data.aws_ami.devstation.name})"
}
