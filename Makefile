.PHONY: clean deploy destroy help init list

# 默认目标
.DEFAULT_GOAL := help

# 帮助信息
help:
	@echo "Terraform Quickstart - Root Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make list               - List all available modules"
	@echo "  make init MODULE=xxx    - Initialize Terraform for specified module"
	@echo "  make deploy MODULE=xxx  - Deploy specified module"
	@echo "  make destroy MODULE=xxx - Destroy specified module"
	@echo "  make clean MODULE=xxx   - Clean Terraform files for specified module"
	@echo "  make clean-all          - Clean Terraform files for all modules"
	@echo "  make help               - Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make init MODULE=vm"
	@echo "  make deploy MODULE=vm"
	@echo "  make destroy MODULE=vmss"
	@echo "  make clean MODULE=vmss"
	@echo "  make clean-all"

# 列出所有可用模块
list:
	@echo "Available modules:"
	@for dir in */; do \
		if [ -f "$${dir}Makefile" ]; then \
			echo "  - $${dir%/}"; \
		fi; \
	done

# 初始化指定模块
init:
ifndef MODULE
	@echo "❌ Error: MODULE parameter is required"
	@echo ""
	@echo "Usage: make init MODULE=<module-name>"
	@echo "Example: make init MODULE=vm"
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
	@echo "Initializing $(MODULE)..."
	@cd $(MODULE) && make init
endif

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
	@echo "Cleaning $(MODULE)/..."
	@cd $(MODULE) && make clean
endif

# 清理所有模块
clean-all:
	@echo "Cleaning all modules..."
	@for dir in */; do \
		if [ -f "$${dir}Makefile" ]; then \
			echo ""; \
			echo "=== Cleaning $${dir%/} ==="; \
			cd "$$dir" && make clean && cd ..; \
		fi; \
	done
	@echo ""
	@echo "✓ All modules cleaned"

# 部署指定模块
deploy:
ifndef MODULE
	@echo "❌ Error: MODULE parameter is required"
	@echo ""
	@echo "Usage: make deploy MODULE=<module-name>"
	@echo "Example: make deploy MODULE=vm"
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
	@echo "Deploying $(MODULE)..."
	@cd $(MODULE) && make deploy
endif

# 销毁指定模块
destroy:
ifndef MODULE
	@echo "❌ Error: MODULE parameter is required"
	@echo ""
	@echo "Usage: make destroy MODULE=<module-name>"
	@echo "Example: make destroy MODULE=vm"
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
	@echo "Destroying $(MODULE)..."
	@cd $(MODULE) && make destroy
endif
