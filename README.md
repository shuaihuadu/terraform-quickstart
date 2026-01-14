# Terraform Azure VMSS Quickstart

一个用于在 Azure 上快速部署 Flexible Virtual Machine Scale Set (VMSS) 的 Terraform 项目，包含 Premium SSD v2 磁盘和自动化的资源可用性检查。

## 功能特性

- ✅ Flexible VMSS with VM profile (支持 Portal 手动扩缩容)
- ✅ Premium SSD v2 磁盘支持（可配置 IOPS 和吞吐量）
- ✅ 自动化的资源可用性检查（避免部署失败）
- ✅ 可用区支持
- ✅ 变量化配置（无需修改代码）
- ✅ 自动化部署和清理脚本

## 快速开始

### 前置要求

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) 已安装并登录
- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- `jq` 命令行工具

### 1. 登录 Azure

```bash
az login
```

### 2. 修改配置

编辑 `terraform.tfvars` 文件：

```hcl
# 基础配置
location = "westus3"          # 修改为您的目标区域
vm_size  = "Standard_D4s_v6"  # 修改为您需要的 VM 规格

# 可用区配置
zones = ["3"]  # 或 null（不使用可用区）

# 其他配置...
```

### 3. 检查资源可用性

**重要**：在部署前先检查资源是否在目标区域可用：

```bash
make check
```

### 4. 部署

```bash
make deploy
```

这会自动：
1. ✅ 检查资源可用性
2. 初始化 Terraform
3. 创建执行计划
4. 部署基础设施
5. 配置 Premium SSD v2 性能参数

### 5. 清理

```bash
make clean    # 清理 Terraform 文件
make destroy  # 销毁所有资源
```

## 可用命令

```bash
make help     # 显示帮助信息
make check    # 检查 Azure 资源可用性
make clean    # 清理 Terraform 文件
make deploy   # 部署基础设施（自动先检查）
make destroy  # 销毁所有资源
```

## 配置说明

所有配置都在 `terraform.tfvars` 中：

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `location` | Azure 区域 | `westus3` |
| `vm_size` | VM 规格 | `Standard_D4s_v6` |
| `instance_count` | 实例数量 | `1` |
| `zones` | 可用区列表 | `["3"]` |
| `disk_size_gb` | 数据磁盘大小(GB) | `100` |
| `disk_iops` | 磁盘 IOPS | `16000` |
| `disk_throughput_mbps` | 磁盘吞吐量(MB/s) | `1000` |

## 资源可用性检查

这个项目包含自动化的资源可用性检查，避免常见的部署错误：

### 检查内容

- ✅ VM SKU 在目标区域的可用性
- ✅ 磁盘类型（Premium SSD v2）的可用性
- ✅ 可用区的兼容性
- ✅ 资源限制和约束

### 常见问题

#### 问题 1: VM SKU 不可用

```
❌ VM SKU 'Standard_D4s_v6' not found in 'eastus'
```

**解决方案**：
- 更换区域：`location = "westus3"`
- 或更换 VM 规格：`vm_size = "Standard_D4s_v5"`

#### 问题 2: 可用区不兼容

```
❌ Zone 3: Incompatible
```

**解决方案**：
- 更换可用区：`zones = ["1"]`
- 或不使用可用区：`zones = null`

查看完整文档：[scripts/README.md](scripts/README.md)

## 项目结构

```
terraform-quickstart/
├── main.tf                        # Terraform 主配置
├── variables.tf                   # 变量定义
├── outputs.tf                     # 输出定义
├── terraform.tfvars               # 配置文件（修改这个！）
├── Makefile                       # 自动化命令
├── scripts/
│   ├── check-availability.sh      # 资源可用性检查
│   ├── deploy.sh                  # 部署脚本
│   ├── clean.sh                   # 清理脚本
│   └── README.md                  # 脚本文档
└── README.md                      # 本文件
```

## 注意事项

### Premium SSD v2 限制

- 不是所有区域都支持 Premium SSD v2
- 建议使用 `westus3`、`westus2`、`eastus2` 等区域
- 如果不需要 Premium SSD v2，可以改用 `Premium_LRS`

### VM SKU 选择

- `Standard_D4s_v6` 是最新的 ARM 架构 VM，性能优异但可用性有限
- 如需更广泛的区域支持，可使用 `Standard_D4s_v5`

### 可用区

- 使用可用区可提高可用性，但会限制 SKU 选择
- 如遇到可用性问题，可设置 `zones = null`

## 部署后

### 查看资源

```bash
# 查看 VMSS
az vmss list -g rg-vmss-pdv2 -o table

# 查看 VM 实例
az vmss list-instances -g rg-vmss-pdv2 -n vmss-pdv2-demo -o table

# 查看磁盘
az disk list -g rg-vmss-pdv2 -o table
```

### 扩缩容

在 Azure Portal 中：
1. 找到 VMSS 资源
2. Settings → Instances
3. 手动调整实例数量

或使用 CLI：
```bash
az vmss scale -g rg-vmss-pdv2 -n vmss-pdv2-demo --new-capacity 3
```

## License

MIT

## 贡献

欢迎提交 Issue 和 Pull Request！
