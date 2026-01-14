.PHONY: clean clean-keys clean-tfstate deploy destroy help init

# 默认目标
.DEFAULT_GOAL := help

# 帮助信息
help:
	@echo "VM Module Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make init         - Initialize Terraform (download providers)"
	@echo "  make deploy       - Deploy infrastructure (init + plan + apply)"
	@echo "  make destroy      - Destroy all infrastructure"
	@echo "  make clean        - Clean all (Terraform files + SSH keys)"
	@echo "  make clean-tfstate - Clean Terraform files only (.terraform, state files)"
	@echo "  make clean-keys   - Clean SSH keys only (id_rsa, *.pem)"
	@echo "  make help         - Show this help message"

# 初始化 Terraform
init:
	@echo "Initializing Terraform..."
	@terraform init

# 清理 Terraform 状态文件
clean-tfstate:
	@echo "Cleaning Terraform files..."
	@../scripts/clean.sh

# 清理 SSH 密钥
clean-keys:
	@echo "Cleaning SSH keys..."
	@rm -f keys/id_rsa keys/id_rsa.pub keys/*.pem 2>/dev/null || true
	@echo "✓ SSH keys cleaned"

# 清理所有（Terraform + SSH 密钥）
clean: clean-tfstate clean-keys
	@echo "✓ All cleaned"

# 部署基础设施
deploy:
	@echo "Deploying infrastructure..."
	@../scripts/deploy.sh

# 销毁基础设施
destroy:
	@echo "Destroying infrastructure..."
	@terraform destroy -auto-approve
