// Reusable general-purpose devstation AMI.

packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "~> 1"
    }
  }
}

variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "manifest_name" {
  type    = string
  default = "manifest.json" // account-specific AMI ids; gitignored
}

variable "instance_type" {
  type    = string
  default = "m7i-flex.large" // builder; deploy size is set independently in Terraform
}

variable "volume_size" {
  type    = number
  default = 30
}

locals {
  ami_name = "devstation-${formatdate("YYYYMMDD-hhmmss", timestamp())}"
}

source "amazon-ebs" "devstation" {
  region        = var.region
  instance_type = var.instance_type
  ami_name      = local.ami_name
  ssh_username  = "ubuntu"

  // Ubuntu 24.04 LTS (noble), official Canonical owner.
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    owners      = ["099720109477"]
    most_recent = true
  }

  // Force IMDSv2 on the builder too (Terraform enforces it again on deploy).
  imds_support = "v2.0"

  // Ubuntu's cloud image defaults to 8 GB. Bake the real size in once so every
  // instance stamped from this AMI gets it; cloud-init grows the fs on boot.
  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Project   = "k8s-lab"
    Role      = "devstation"
    ManagedBy = "packer"
    BaseOS    = "ubuntu-24.04"
  }
}

build {
  name    = "devstation"
  sources = ["source.amazon-ebs.devstation"]

  provisioner "ansible" {
    playbook_file = "${path.root}/ansible/playbook.yaml"
    use_proxy     = false
  }

  // Record the new AMI id so Terraform's data source has something to find.
  post-processor "manifest" {
    output     = "${path.root}/${var.manifest_name}"
    strip_path = true
  }
}
