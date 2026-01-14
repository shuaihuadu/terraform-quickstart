# Azure Resource Availability Check

这个脚本在部署前验证 Azure 资源的可用性，避免部署失败。

## 功能

- ✅ 检查 VM SKU 在指定区域的可用性
- ✅ 检查磁盘类型在指定区域的可用性  
- ✅ 验证可用区的兼容性
- ✅ 检测资源限制和约束
- ✅ 提供友好的错误提示和建议

## 使用方法

### 方法 1：直接运行脚本

```bash
./scripts/check-availability.sh
```

### 方法 2：通过 Makefile

```bash
# 仅检查
make check

# 检查并部署（自动先检查再部署）
make deploy
```

## 检查内容

脚本会从 `terraform.tfvars` 读取配置并检查：

1. **VM SKU 可用性**
   - 检查 VM 规格是否在目标区域可用
   - 验证是否有容量限制

2. **磁盘 SKU 可用性**
   - 检查磁盘类型（如 PremiumV2_LRS）是否可用
   - 验证磁盘限制

3. **可用区兼容性**
   - 验证 VM 和磁盘在指定可用区的兼容性
   - 提供可用区建议

## 输出示例

### ✅ 检查通过
```
======================================
Azure Resource Availability Check
======================================

Configuration:
  Location: westus3
  VM Size: Standard_D4s_v6
  Disk Type: PremiumV2_LRS
  Target Zones: 3

✓ Logged in to Azure
  Subscription: xxx

1. Checking VM SKU availability...
✓ VM SKU 'Standard_D4s_v6' is available
  Available zones: [2, 3, 1]

2. Checking Disk SKU availability...
✓ Disk type 'PremiumV2_LRS' is available
  Available zones: [1, 2, 3]

3. Checking Zone compatibility...
  Checking zone 3...
    ✓ Zone 3: Both VM and Disk supported

======================================
✅ All checks passed!
======================================

You can proceed with deployment:
  make deploy
```

### ❌ 检查失败
```
1. Checking VM SKU availability...
❌ VM SKU has restrictions in 'eastus'

💡 Zone restrictions detected
   Try: zones = null  (in terraform.tfvars)
```

## 常见问题解决

### VM SKU 不可用

**问题**：`❌ VM SKU 'Standard_D4s_v6' not found in 'eastus'`

**解决方案**：
```bash
# 方案 1: 更换区域
location = "westus3"

# 方案 2: 更换 VM 规格
vm_size = "Standard_D4s_v5"
```

### 磁盘类型不可用

**问题**：`❌ Disk type 'PremiumV2_LRS' not available`

**解决方案**：
```bash
# 使用 Premium SSD v1
# 在 main.tf 中修改: storage_account_type = "Premium_LRS"
```

### 可用区不兼容

**问题**：`❌ Zone 3: Incompatible`

**解决方案**：
```bash
# 方案 1: 更换可用区
zones = ["1"]

# 方案 2: 不使用可用区
zones = null
```

## 依赖

- Azure CLI (`az`)
- jq (JSON 处理)
- 已登录 Azure (`az login`)

## 集成到 CI/CD

可以在 CI/CD 管道中使用：

```yaml
# GitHub Actions 示例
- name: Check Azure Resource Availability
  run: ./scripts/check-availability.sh
  
- name: Deploy Infrastructure
  if: success()
  run: make deploy
```

## 手动检查命令

如果需要手动检查特定资源：

```bash
# 检查 VM SKU
az vm list-skus \
  --location westus3 \
  --size Standard_D4s_v6 \
  --all \
  --output table

# 检查磁盘 SKU
az vm list-skus \
  --location westus3 \
  --resource-type disks \
  --query "[?name=='PremiumV2_LRS']" \
  --output table

# 检查可用区
az vm list-skus \
  --location westus3 \
  --zone 3 \
  --all \
  --query "[?name=='Standard_D4s_v6' || name=='PremiumV2_LRS']" \
  --output table
```
