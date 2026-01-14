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
	@./scripts/check-vmss-disk-availability.sh

# 清理 Terraform 文件
clean:
	@echo "Cleaning Terraform files..."
	@./scripts/clean.sh

# 部署基础设施 (先检查再部署)
deploy: check
	@echo "Deploying infrastructure..."
	@./scripts/deploy.sh

# 销毁基础设施
destroy:
	@echo "Destroying infrastructure..."
	@terraform destroy -auto-approve
