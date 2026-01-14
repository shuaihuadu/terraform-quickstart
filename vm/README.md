# VM 模块 - 单虚拟机部署

在 Azure 上快速部署单个 Linux 虚拟机，支持多种磁盘类型和网络配置。

## 功能特性

- ✅ 单 Linux VM 部署
- ✅ 支持多种磁盘类型 (Premium_LRS, PremiumV2_LRS, StandardSSD_LRS)
- ✅ 可选公网 IP
- ✅ 可选数据磁盘
- ✅ 可用区支持
- ✅ NSG 自动配置 (SSH)

## 快速开始

### 1. 修改配置

编辑 `terraform.tfvars` 文件：

```hcl
# 基础配置
location = "westus3"
vm_size  = "Standard_D4s_v5"
vm_name  = "my-vm"

# 启用公网 IP
enable_public_ip = true

# 添加数据磁盘 (可选)
data_disk_size_gb = 100
data_disk_type    = "Premium_LRS"
```

### 2. 部署

```bash
make deploy
```

### 3. 连接 VM

部署完成后会输出 SSH 连接命令：

```bash
ssh azureuser@<public-ip>
```

### 4. 销毁

```bash
make destroy
```

## 可用命令

```bash
make help     # 显示帮助信息
make clean    # 清理 Terraform 文件
make deploy   # 部署基础设施
make destroy  # 销毁所有资源
```

## 配置说明

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `location` | Azure 区域 | `westus3` |
| `vm_size` | VM 规格 | `Standard_D4s_v5` |
| `vm_name` | VM 名称 | `vm-demo` |
| `zone` | 可用区 (1/2/3/null) | `null` |
| `os_disk_type` | OS 磁盘类型 | `Premium_LRS` |
| `data_disk_size_gb` | 数据磁盘大小 | `null` (不创建) |
| `data_disk_type` | 数据磁盘类型 | `Premium_LRS` |
| `enable_public_ip` | 是否创建公网 IP | `true` |

## 使用 Premium SSD v2

如需高性能数据磁盘：

```hcl
zone              = "1"           # 必须指定可用区
data_disk_size_gb = 100
data_disk_type    = "PremiumV2_LRS"
data_disk_iops    = 5000
data_disk_mbps    = 200
```

## 部署后验证

```bash
# 查看 VM
az vm list -g rg-vm-demo -o table

# 查看磁盘
az disk list -g rg-vm-demo -o table

# 查看公网 IP
az network public-ip list -g rg-vm-demo -o table
```

## 文件结构

```
vm/
├── Makefile           # 构建命令
├── main.tf            # Terraform 主配置
├── variables.tf       # 变量定义
├── outputs.tf         # 输出定义
├── terraform.tfvars   # 配置文件（修改这个！）
└── README.md          # 本文件
```
