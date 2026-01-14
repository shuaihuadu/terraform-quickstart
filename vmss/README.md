# VMSS 模块 - Flexible VMSS + Premium SSD v2

在 Azure 上快速部署 Flexible Virtual Machine Scale Set (VMSS)，支持 Premium SSD v2 磁盘和自动化的资源可用性检查。

## 功能特性

- ✅ Flexible VMSS with VM profile (支持 Portal 手动扩缩容)
- ✅ Premium SSD v2 磁盘支持（可配置 IOPS 和吞吐量）
- ✅ 自动化的资源可用性检查（避免部署失败）
- ✅ 可用区支持
- ✅ 变量化配置（无需修改代码）
- ✅ 手动扩容脚本（带磁盘性能自动更新）

## 快速开始

### 1. 修改配置

编辑 `terraform.tfvars` 文件：

```hcl
# 基础配置
location = "westus3"          # 修改为您的目标区域
vm_size  = "Standard_D4s_v6"  # 修改为您需要的 VM 规格

# 可用区配置
zones = ["3"]  # 或 null（不使用可用区）

# 磁盘性能
disk_iops = 16000
disk_throughput_mbps = 1000
```

### 2. 检查资源可用性

**重要**：在部署前先检查资源是否在目标区域可用：

```bash
make check
```

### 3. 部署

```bash
make deploy
```

这会自动：
1. ✅ 检查资源可用性
2. 初始化 Terraform
3. 创建执行计划
4. 部署基础设施
5. 配置 Premium SSD v2 性能参数

### 4. 销毁

```bash
make destroy
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
| `instance_count` | 实例数量 | `2` |
| `zones` | 可用区列表 | `["3"]` |
| `disk_size_gb` | 数据磁盘大小(GB) | `100` |
| `disk_iops` | 磁盘 IOPS | `16000` |
| `disk_throughput_mbps` | 磁盘吞吐量(MB/s) | `1000` |

## 手动扩容

部署后如需扩容并保持磁盘性能配置：

```bash
# 扩容到 4 个实例
../scripts/vmss/scale-vmss.sh -g rg-vmss-pdv2 -n vmss-pdv2-demo -c 4 --iops 16000 --mbps 1000

# 仅更新现有磁盘性能
../scripts/vmss/scale-vmss.sh -g rg-vmss-pdv2 -n vmss-pdv2-demo --update-only --iops 20000 --mbps 1200

# 查看帮助
../scripts/vmss/scale-vmss.sh --help
```

## 部署后验证

```bash
# 查看 VMSS
az vmss list -g rg-vmss-pdv2 -o table

# 查看 VM 实例
az vm list -g rg-vmss-pdv2 -o table

# 查看磁盘性能
az disk list -g rg-vmss-pdv2 --query "[].{Name:name, IOPS:diskIOPSReadWrite, MBPS:diskMBpsReadWrite}" -o table
```

## 常见问题

### VM SKU 不可用

```
❌ VM SKU 'Standard_D4s_v6' not found in 'eastus'
```

**解决方案**：更换区域或 VM 规格
```hcl
location = "westus3"
# 或
vm_size = "Standard_D4s_v5"
```

### 可用区不兼容

```
❌ Zone 3: Incompatible
```

**解决方案**：更换可用区或不使用可用区
```hcl
zones = ["1"]
# 或
zones = null
```

### Premium SSD v2 不支持

某些区域不支持 Premium SSD v2，建议使用：
- `westus3`
- `westus2`
- `eastus2`

详细的可用性检查文档见：[../scripts/vmss/README.md](../scripts/vmss/README.md)

## 文件结构

```
vmss/
├── Makefile           # 构建命令
├── main.tf            # Terraform 主配置
├── variables.tf       # 变量定义
├── outputs.tf         # 输出定义
├── terraform.tfvars   # 配置文件（修改这个！）
└── README.md          # 本文件
```
