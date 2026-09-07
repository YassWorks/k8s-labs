// Stamps N identical devstations from the latest self-built devstation AMI.
// Deliberately minimal: default VPC, no networking to build or tear down, and
// nothing Kubernetes-aware. Terraform's job ends at "here are your boxes and
// the key to reach them".

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws   = { source = "hashicorp/aws", version = ">= 5.40" }
    tls   = { source = "hashicorp/tls", version = "~> 4.0" }
    local = { source = "hashicorp/local", version = "~> 2.4" }
  }
}

provider "aws" {
  region = var.region
}

// --- Inputs discovered at plan time ---

// The handoff from Packer: always the newest image we built ourselves.
data "aws_ami" "devstation" {
  owners      = ["self"]
  most_recent = true

  filter {
    name   = "name"
    values = ["devstation-*"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

locals {
  // All nodes share one subnet: same AZ means no cross-AZ data transfer
  // charges when they talk to each other. sort() keeps the pick stable.
  subnet_id = sort(data.aws_subnets.default.ids)[0]
}

// --- Access ---

resource "tls_private_key" "devstation" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "devstation" {
  key_name_prefix = "${var.node_prefix}-"
  public_key      = tls_private_key.devstation.public_key_openssh
}

resource "local_sensitive_file" "pem" {
  filename             = pathexpand("~/.ssh/devstation.pem")
  content              = tls_private_key.devstation.private_key_openssh
  file_permission      = "0400"
  directory_permission = "0700"
}

// --- Security group ---

resource "aws_security_group" "devstation" {
  name_prefix = "${var.node_prefix}-"
  description = "devstation: ssh in, unrestricted between nodes, open egress"
  vpc_id      = data.aws_vpc.default.id

  tags = { Name = var.node_prefix }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.devstation.id
  description       = "ssh from the operator"
  cidr_ipv4         = var.allowed_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

// Everything between nodes, on every port. This is what lets you build a
// cluster on top later without Terraform ever knowing a Kubernetes port number.
resource "aws_vpc_security_group_ingress_rule" "internode" {
  security_group_id            = aws_security_group.devstation.id
  description                  = "unrestricted node-to-node"
  referenced_security_group_id = aws_security_group.devstation.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.devstation.id
  description       = "all egress"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

// --- Nodes ---

resource "aws_instance" "node" {
  count = var.node_count

  ami                    = data.aws_ami.devstation.id
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.devstation.id]
  key_name               = aws_key_pair.devstation.key_name

  // associate_public_ip_address is deliberately unset. It is ForceNew, and the
  // provider reads it back from the ENI's association, which AWS releases while
  // an instance is stopped. Setting it true means every stopped node plans as a
  // replacement, terminating it and deleting its root volume. Default VPC
  // subnets have map_public_ip_on_launch, so nodes still get a public IP.

  root_block_device {
    volume_size           = var.volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" // IMDSv2
  }

  // Sets the hostname so the login banner tells you which box you're on.
  user_data = <<-EOT
    #cloud-config
    hostname: ${var.node_prefix}-${count.index}
    fqdn: ${var.node_prefix}-${count.index}
    preserve_hostname: false
  EOT

  tags = {
    Name      = "${var.node_prefix}-${count.index}"
    Project   = "k8s-lab"
    ManagedBy = "terraform"
  }
}

// Stopping is not destroying: the instance, its ENI and its root volume all
// survive, so the private IP holds and only the compute charge goes away. The
// public IP does not survive, which is why `make ip` refreshes before printing.
resource "aws_ec2_instance_state" "node" {
  count = var.node_count

  instance_id = aws_instance.node[count.index].id
  state       = contains(var.stopped_nodes, count.index) ? "stopped" : "running"
}
