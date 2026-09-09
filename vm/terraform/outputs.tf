output "nodes" {
  description = "Node name -> public IP, or \"stopped\"."
  value = {
    for idx, node in aws_instance.node :
    node.tags.Name => contains(var.stopped_nodes, idx) ? "stopped" : node.public_ip
  }
}

output "private_ips" {
  description = "Node name -> private IP (what the nodes use to reach each other)."
  value       = { for i in aws_instance.node : i.tags.Name => i.private_ip }
}

output "node_count" {
  description = "How many nodes exist, so tooling can bounds-check an index."
  value       = var.node_count
}

output "node_prefix" {
  description = "Name prefix, so tooling can turn an index back into a node name."
  value       = var.node_prefix
}

output "pem" {
  description = "Path to the generated private key."
  value       = local_sensitive_file.pem.filename
}

output "ami" {
  description = "AMI the nodes were stamped from."
  value       = "${data.aws_ami.devstation.id} (${data.aws_ami.devstation.name})"
}
