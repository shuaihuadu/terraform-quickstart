.PHONY: clean help list

# 默认目标
.DEFAULT_GOAL := help

# 帮助信息
help:
	@echo "Terraform Quickstart - Root Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make list              - List all available modules"
	@echo "  make clean MODULE=xxx  - Clean Terraform files for specified module"
	@echo "  make clean-all         - Clean Terraform files for all modules"
	@echo "  make help              - Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make clean MODULE=vmss"
	@echo "  make clean MODULE=redis"
	@echo "  make clean-all"
	@echo ""
	@echo "For module-specific operations (deploy, destroy, check):"
	@echo "  cd <module> && make deploy"
	@echo "  cd vmss && make deploy"

# 列出所有可用模块
list:
	@echo "Available modules:"
	@for dir in */; do \
		if [ -f "$${dir}Makefile" ]; then \
			echo "  - $${dir%/}"; \
		fi; \
	done

# 清理指定模块
clean:
ifndef MODULE
	@echo "❌ Error: MODULE parameter is required"
	@echo ""
	@echo "Usage: make clean MODULE=<module-name>"
	@echo "Example: make clean MODULE=vmss"
	@echo ""
	@echo "Available modules:"
	@for dir in */; do \
		if [ -f "$${dir}Makefile" ]; then \
			echo "  - $${dir%/}"; \
		fi; \
	done
	@exit 1
else
	@if [ ! -d "$(MODULE)" ]; then \
		echo "❌ Error: Module '$(MODULE)' not found"; \
		exit 1; \
	fi
	@echo "Cleaning Terraform files in $(MODULE)/..."
	@cd $(MODULE) && ../scripts/clean.sh
endif

# 清理所有模块
clean-all:
	@echo "Cleaning all modules..."
	@for dir in */; do \
		if [ -f "$${dir}Makefile" ]; then \
			echo ""; \
			echo "=== Cleaning $${dir%/} ==="; \
			cd "$$dir" && ../scripts/clean.sh && cd ..; \
		fi; \
	done
	@echo ""
	@echo "✓ All modules cleaned"
