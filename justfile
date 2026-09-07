packer_dir := "vm/packer"
tf_dir     := "vm/terraform"
state_file := tf_dir / "stopped.auto.tfvars"

_default:
    @just --list --unsorted

# build the devstation AMI (packer + ansible)
ami:
    cd {{packer_dir}} && packer init . && packer build devstation.pkr.hcl

# stamp out the nodes
up:
    cd {{tf_dir}} && terraform init -input=false && terraform apply -auto-approve

# destroy the nodes, disks included
[confirm]
down:
    cd {{tf_dir}} && terraform destroy -auto-approve
    rm -f {{state_file}}

# stop nodes but keep their disks: `just stop 1 2`
stop +nodes:
    #!/usr/bin/env bash
    set -eu
    just _check {{nodes}}
    echo "stopped_nodes = [$(echo $(just _stopped) {{nodes}} | tr ' ' '\n' | grep -v '^$' | sort -nu | paste -sd, -)]" > {{state_file}}
    just _apply
    just ip

# bring stopped nodes back: `just start 1`
start +nodes:
    #!/usr/bin/env bash
    set -eu
    just _check {{nodes}}
    keep=$(echo $(just _stopped) | tr ' ' '\n' | grep -vxF -f <(echo {{nodes}} | tr ' ' '\n') || true)
    echo "stopped_nodes = [$(echo $keep | tr ' ' '\n' | grep -v '^$' | sort -nu | paste -sd, -)]" > {{state_file}}
    just _apply
    just ip

# print node name -> public IP, or 'stopped'
ip:
    @cd {{tf_dir}} && terraform apply -refresh-only -auto-approve >/dev/null && terraform output nodes

# print your public IP, for allowed_cidr
myip:
    @curl -s https://checkip.amazonaws.com

# format the HCL
fmt:
    cd {{packer_dir}} && packer fmt .
    cd {{tf_dir}} && terraform fmt

# Indices currently marked stopped, read back out of the generated tfvars.
[private]
_stopped:
    @sed -n 's/^stopped_nodes *= *\[\(.*\)\]/\1/p' {{state_file}} 2>/dev/null | tr ',' ' '

# Applies the current config, but refuses if the plan would destroy anything.
# stop and start are lifecycle operations: no node should ever be replaced by
# one, and a silent replacement takes the root volume with it.
[private]
_apply:
    #!/usr/bin/env bash
    set -eu
    cd {{tf_dir}}
    trap 'rm -f .tfplan' EXIT
    terraform plan -input=false -out=.tfplan >/dev/null
    if terraform show -json .tfplan | grep -qE '"actions": *\[[^]]*"delete"'; then
        echo "refusing to apply: this plan destroys or replaces a resource." >&2
        echo "inspect it with: cd {{tf_dir}} && terraform plan" >&2
        exit 1
    fi
    terraform apply -input=false .tfplan

# Fails unless every argument is an index of a node that actually exists.
[private]
_check +nodes:
    #!/usr/bin/env bash
    set -eu
    count=$(cd {{tf_dir}} && terraform output -raw node_count 2>/dev/null) \
        || { echo "cannot read node_count: run 'just up' first" >&2; exit 1; }
    for n in {{nodes}}; do
        case $n in ''|*[!0-9]*) echo "not a node index: $n" >&2; exit 1 ;; esac
        [ "$n" -lt "$count" ] \
            || { echo "no such node: $n (have 0..$((count - 1)))" >&2; exit 1; }
    done
