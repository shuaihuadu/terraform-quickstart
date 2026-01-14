# Terraform Azure Quickstart

Azure 资源的 Terraform 快速部署模板集合，每个模块完全自包含，可独立使用。

## 可用模块

| 模块 | 说明 | 状态 |
|------|------|------|
| [vmss/](vmss/) | Flexible VMSS + Premium SSD v2 | ✅ 可用 |
| vm/ | 单 VM 部署 | 🔜 计划中 |
| redis/ | Azure Redis Cache | 🔜 计划中 |
| postgres/ | Azure Database for PostgreSQL | 🔜 计划中 |
| sql-server/ | Azure SQL Server | 🔜 计划中 |

## 快速开始

### 前置要求

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) 已安装并登录
- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- `jq` 命令行工具

### 登录 Azure

```bash
az login
```

### 使用模块

```bash
# 进入模块目录
cd vmss

# 查看可用命令
make help

# 检查资源可用性
make check

# 部署
make deploy

# 销毁
make destroy
```

## 根目录命令

```bash
make help              # 显示帮助
make list              # 列出所有可用模块
make clean MODULE=vmss # 清理指定模块的 tfstate
make clean-all         # 清理所有模块
```

## 项目结构

```
terraform-quickstart/
├── Makefile                 # 根目录管理命令
├── README.md                # 本文件
├── scripts/
│   ├── clean.sh             # 通用清理脚本
│   ├── deploy.sh            # 通用部署脚本
│   └── vmss/                # VMSS 专用脚本
│       ├── check-vmss-disk-availability.sh
│       ├── scale-vmss.sh
│       ├── update-disk-performance.sh
│       └── README.md
└── vmss/                    # VMSS 模块
    ├── Makefile
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── terraform.tfvars
    └── README.md
```

## 添加新模块

1. 创建模块目录：`mkdir <module-name>`
2. 添加 Terraform 文件和 Makefile
3. 如需专用脚本，创建 `scripts/<module-name>/`
4. 模块会自动被 `make list` 识别

## License

MIT
