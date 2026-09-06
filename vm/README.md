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
packer version && terraform version && aws --version && ansible --version && make -v
# install whatever is missing, then authenticate
aws configure     # or: aws configure sso
```

## Use

```bash
make ami                                 # ~5 min, once
cp vm/terraform/terraform.tfvars{.example,}
make myip                                # paste the result into allowed_cidr
make up                                  # ~40 s
make ip
ssh -i ~/.ssh/devstation.pem ubuntu@<ip>
make down
```

`make ami` is only needed when the image contents change. Day to day it's `make up` / `make down`.

### The key

Terraform generates an ED25519 keypair and writes `~/.ssh/devstation.pem` at mode `0400`, ready to use with no copying or `chmod`. It goes to your home directory rather than the repo because Windows drives mount `0777` under WSL, and OpenSSH refuses a key that loose.

- The private key is also stored **in plaintext in `terraform.tfstate`**, which is gitignored. Treat the state file as a secret.
- `make down` deletes the key, since Terraform manages the file. A later `make up` generates a **new** one, so any copy you kept stops working.

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
