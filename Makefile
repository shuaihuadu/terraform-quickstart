.PHONY: clean deploy destroy help check

# 默认目标
.DEFAULT_GOAL := help

# 帮助信息
help:
	@echo "Terraform Project Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make check   - Check Azure resource availability (VM SKU, Disk, Zones)"
	@echo "  make clean   - Clean Terraform files (.terraform, state files, etc.)"
	@echo "  make deploy  - Deploy infrastructure (check + init + plan + apply)"
	@echo "  make destroy - Destroy all infrastructure"
	@echo "  make help    - Show this help message"

# 检查 Azure 资源可用性
check:
	@echo "Checking Azure resource availability..."
	@VM_SKU=$$(grep '^vm_size' vmss/terraform.tfvars | cut -d'"' -f2); \
	REGION=$$(grep '^location' vmss/terraform.tfvars | cut -d'"' -f2); \
	ZONES=$$(grep '^zones' vmss/terraform.tfvars | grep -oP '\[.*\]' | tr -d '[]" ' | tr '\n' ','); \
	./scripts/vmss/check-vmss-disk-availability.sh "$$VM_SKU" "$$REGION" "$$ZONES"

# 清理 Terraform 文件
clean:
	@echo "Cleaning Terraform files..."
	@cd vmss && ../scripts/clean.sh

# 部署基础设施 (先检查再部署)
deploy: check
	@echo "Deploying infrastructure..."
	@cd vmss && ../scripts/deploy.sh

# 销毁基础设施
destroy:
	@echo "Destroying infrastructure..."
	@cd vmss && terraform destroy -auto-approve
