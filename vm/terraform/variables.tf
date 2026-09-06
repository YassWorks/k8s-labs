variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "node_count" {
  type        = number
  description = "How many devstations to stamp out."
  default     = 3
}

// Written by `make stop` / `make start` into stopped.auto.tfvars, which
// Terraform auto-loads. It lives on disk because the choice has to survive
// between shell sessions; a -var flag would not.
variable "stopped_nodes" {
  type        = list(number)
  description = "Indices of nodes to keep stopped."
  default     = []
}

variable "node_prefix" {
  type        = string
  description = "Names nodes <prefix>-0..N, and the generated <prefix>.pem."
  default     = "dev"
}

variable "instance_type" {
  type    = string
  default = "m7i-flex.large"
}

variable "volume_size" {
  type    = number
  default = 30
}

// No default on purpose: 0.0.0.0/0 would put SSH in front of the whole
// internet. Get yours with `curl -s https://checkip.amazonaws.com`.
variable "allowed_cidr" {
  type        = string
  description = "CIDR permitted to SSH in."

  validation {
    condition     = can(cidrnetmask(var.allowed_cidr))
    error_message = "allowed_cidr must be valid CIDR notation."
  }
}
