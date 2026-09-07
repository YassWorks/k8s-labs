# devstation

Reusable EC2 dev boxes, built once with Packer + Ansible and stamped out N at a time with Terraform. Built to give me identical Linux nodes for learning Kubernetes, and a throwaway dev box for anything else afterwards.

**The image contains no Kubernetes.** No kubeadm, no containerd tuning, no sysctls, no swap policy, no CNI. Terraform gives you boxes and a key; the cluster is a manual exercise on top, which is the entire point.

```
vm/
|-- packer/            devstation-<timestamp> AMI
|   |-- devstation.pkr.hcl
|   |__ ansible/       roles: common, cleanup
|__ terraform/         N nodes in the default VPC + a generated .pem
```

## What's in the image

Ubuntu 24.04 LTS, amd64, 30 GB gp3.

- `build-essential git curl wget jq htop tmux vim tree rsync ncdu unzip`
- Docker CE (+ buildx, compose), `ubuntu` in the `docker` group
- [uv](https://docs.astral.sh/uv/)
- UTC + time sync, unattended-upgrades disabled, a compact login banner

## Prerequisites

Run everything from **WSL Ubuntu-24.04**. Ansible has no native Windows build and Packer shells out to `ansible-playbook`, so a Windows-side Packer fails with `exec: "ansible-playbook": executable file not found in %PATH%`.

```bash
# inside WSL, the toolchain
packer version && terraform version && aws --version && ansible --version && just --version
# install whatever is missing, then authenticate
aws configure     # or: aws configure sso
```

## Use

```bash
just ami                                 # ~5 min, once
cp vm/terraform/terraform.tfvars{.example,}
just myip                                # paste the result into allowed_cidr
just up                                  # ~40 s
just ip
ssh -i ~/.ssh/devstation.pem ubuntu@<ip>
just down
```

`just` with no arguments lists every recipe. `just ami` is only needed when the image contents change. Day to day it's `just up` / `just down`.

### Pausing without destroying

`just down` terminates everything: the disks go too, and the next `just up` is a blank box. To keep your work but stop paying for compute, stop the nodes instead.

```bash
just stop 1 2   # or a single node
just ip         # dev-0 -> 13.51.x.x, dev-1 -> stopped
just start 1    # prints the new IP when it's back
```

Nodes are named by index, the `N` in `dev-N`. The state lives in `vm/terraform/stopped.auto.tfvars`, which Terraform auto-loads, so a stopped node stays stopped across `just up` and across reboots of your own machine.

- **A stopped node still bills for its EBS root volume**, roughly $2.40/month per 30 GB in `eu-north-1`. Only the instance-hour charge goes away.
- The **public IP changes** on every start, since there is no Elastic IP. `just ip` refreshes Terraform's state before printing, so it is never stale. An EIP would pin the address but costs ~$3.65/month per node while stopped, which is more than the disk.
- The **private IP does not change**. It lives on the ENI, which stays attached, so anything the nodes use to reach each other survives a stop.
- `stop` and `start` plan first and **refuse to apply if the plan would destroy or replace anything**. A lifecycle command must never terminate a node, because `delete_on_termination` would take the root volume with it. If you hit that refusal, run `terraform plan` in `vm/terraform` and find out what drifted before forcing anything.

### The key

Terraform generates an ED25519 keypair and writes `~/.ssh/devstation.pem` at mode `0400`, ready to use with no copying or `chmod`. It goes to your home directory rather than the repo because Windows drives mount `0777` under WSL, and OpenSSH refuses a key that loose.

- The private key is also stored **in plaintext in `terraform.tfstate`**, which is gitignored. Treat the state file as a secret.
- `just down` deletes the key, since Terraform manages the file. A later `just up` generates a **new** one, so any copy you kept stops working.

## Networking

Default VPC, all nodes in one subnet (same AZ, so no cross-AZ transfer charges). The security group allows SSH from `allowed_cidr`, **all traffic between nodes**, and all egress. That inter-node rule is what lets you build a cluster later without Terraform knowing any Kubernetes port numbers.

## Rebuilding the image

The `cleanup` Ansible role runs last and strips the builder's identity, machine-id, SSH host keys, cloud-init state, `authorized_keys`. Without it every node would share a machine-id and the same SSH host keys, so your client couldn't tell them apart. After any image change, verify it took:

```bash
for n in 0 1; do
  ssh -i ~/.ssh/devstation.pem ubuntu@$IP "cat /etc/machine-id; sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub"
done
```

The values must differ between nodes. If they match, `cleanup` didn't run last.
