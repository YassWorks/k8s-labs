PACKER_DIR := vm/packer
TF_DIR     := vm/terraform

.PHONY: help ami up down ip fmt myip

help:
	@echo "ami    build the devstation AMI (packer + ansible)"
	@echo "up     stamp out the nodes (terraform apply)"
	@echo "down   destroy the nodes (terraform destroy)"
	@echo "ip     print node name -> public IP"
	@echo "myip   print your public IP, for allowed_cidr"
	@echo "fmt    format the HCL"

ami:
	cd $(PACKER_DIR) && packer init . && packer build devstation.pkr.hcl

up:
	cd $(TF_DIR) && terraform init -input=false && terraform apply -auto-approve

down:
	cd $(TF_DIR) && terraform destroy -auto-approve

ip:
	@cd $(TF_DIR) && terraform output nodes

myip:
	@curl -s https://checkip.amazonaws.com

fmt:
	cd $(PACKER_DIR) && packer fmt .
	cd $(TF_DIR) && terraform fmt
