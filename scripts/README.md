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

## 高级检测方法

### 查找 VM 支持但 Premium SSD v2 不支持的区域

如果需要分析哪些区域存在兼容性问题，可以使用以下方法：

#### 方法 1: 查询所有区域并比较

```bash
# 1. 查询 VM SKU 支持的所有区域
az vm list-skus \
  --size Standard_D4s_v6 \
  --all \
  --query "[].locationInfo[0].location" -o tsv | \
  tr '[:upper:]' '[:lower:]' | \
  sort -u > vm_regions.txt

# 2. 查询 Premium SSD v2 支持的所有区域
az vm list-skus \
  --resource-type disks \
  --all \
  --query "[?name=='PremiumV2_LRS'].locationInfo[0].location" -o tsv | \
  tr '[:upper:]' '[:lower:]' | \
  sort -u > disk_regions.txt

# 3. 找出差异（VM 支持但磁盘不支持的区域）
comm -23 vm_regions.txt disk_regions.txt

# 清理临时文件
rm vm_regions.txt disk_regions.txt
```

**预期输出**（示例）：
```
australiacentral
belgiumcentral
francesouth
germanynorth
southafricawest
southindia
uaecentral
```

#### 方法 2: 验证特定区域的兼容性

```bash
# 设置要检查的区域
REGION="southindia"

echo "=== 检查 $REGION 的资源可用性 ==="

# 检查 VM SKU
echo "1. VM SKU (Standard_D4s_v6):"
VM_RESULT=$(az vm list-skus \
  --location $REGION \
  --size Standard_D4s_v6 \
  --all \
  --query "[0].name" -o tsv 2>/dev/null)

if [ -n "$VM_RESULT" ]; then
  echo "   ✅ 支持"
else
  echo "   ❌ 不支持"
fi

# 检查磁盘 SKU
echo "2. Premium SSD v2:"
DISK_RESULT=$(az vm list-skus \
  --location $REGION \
  --resource-type disks \
  --all \
  --query "[?name=='PremiumV2_LRS']" -o json)

if [ "$DISK_RESULT" != "[]" ]; then
  echo "   ✅ 支持"
else
  echo "   ❌ 不支持"
  echo "   可用的磁盘类型："
  az vm list-skus \
    --location $REGION \
    --resource-type disks \
    --query "[].name" -o tsv | sort -u
fi
```

#### 方法 3: 批量检查多个区域

```bash
#!/bin/bash

# 要检查的区域列表
REGIONS=(
  "eastus"
  "westus3"
  "northeurope"
  "southindia"
  "japaneast"
)

echo "╔════════════════════════════════════════════════════════╗"
echo "║         区域兼容性检查                                  ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
printf "%-20s %-20s %-20s\n" "区域" "VM SKU" "Premium SSD v2"
printf "%-20s %-20s %-20s\n" "--------------------" "--------------------" "--------------------"

for region in "${REGIONS[@]}"; do
  # 检查 VM
  VM_STATUS="❌ 不支持"
  if az vm list-skus --location $region --size Standard_D4s_v6 --all \
     --query "[0].name" -o tsv 2>/dev/null | grep -q "Standard_D4s_v6"; then
    VM_STATUS="✅ 支持"
  fi
  
  # 检查磁盘
  DISK_STATUS="❌ 不支持"
  DISK_RESULT=$(az vm list-skus --location $region --resource-type disks --all \
    --query "[?name=='PremiumV2_LRS']" -o json 2>/dev/null)
  if [ "$DISK_RESULT" != "[]" ] && [ -n "$DISK_RESULT" ]; then
    DISK_STATUS="✅ 支持"
  fi
  
  printf "%-20s %-20s %-20s\n" "$region" "$VM_STATUS" "$DISK_STATUS"
done
```

#### 方法 4: 查询全球 Premium SSD v2 覆盖情况

```bash
# 查看 Premium SSD v2 在全球的分布
az vm list-skus \
  --resource-type disks \
  --all \
  --query "[?name=='PremiumV2_LRS'].{Region:locationInfo[0].location, Zones:locationInfo[0].zones}" \
  --output table

# 统计支持的区域数量
echo "Premium SSD v2 支持的区域总数："
az vm list-skus \
  --resource-type disks \
  --all \
  --query "[?name=='PremiumV2_LRS'].locationInfo[0].location" \
  -o tsv | wc -l
```

### 测试验证脚本

测试检查脚本是否能正确检测到问题：

```bash
# 1. 备份当前配置
cp terraform.tfvars terraform.tfvars.backup

# 2. 修改为已知不兼容的区域
cat > terraform.tfvars << 'EOF'
resource_group_name = "rg-vmss-test"
location            = "southindia"  # VM 支持但 P2 磁盘不支持
vm_size             = "Standard_D4s_v6"
instance_count      = 1
zones               = ["1"]
disk_size_gb        = 100
disk_iops           = 16000
disk_throughput_mbps = 1000
admin_username      = "azureuser"
admin_password      = "TestPassword123!"
EOF

# 3. 运行检查（应该失败）
./scripts/check-availability.sh

# 预期结果：
# ✅ VM SKU 'Standard_D4s_v6' is available
# ❌ Disk type 'PremiumV2_LRS' not available in 'southindia'
# 💡 Suggestion: Use Premium_LRS instead of PremiumV2_LRS

# 4. 恢复配置
mv terraform.tfvars.backup terraform.tfvars
```

### 已知的不兼容区域（2026年1月）

以下区域 **仅支持 VM 但不支持 Premium SSD v2**：

| 区域 | 说明 | 替代方案 |
|------|------|----------|
| `australiacentral` | 澳大利亚中部 | 使用 `australiaeast` 或 `Premium_LRS` |
| `belgiumcentral` | 比利时中部 | 使用 `westeurope` 或 `Premium_LRS` |
| `francesouth` | 法国南部 | 使用 `francecentral` |
| `germanynorth` | 德国北部 | 使用 `germanywestcentral` |
| `southafricawest` | 南非西部 | 使用 `southafricanorth` |
| `southindia` | 印度南部 | 使用 `centralindia` 或 `Premium_LRS` |
| `uaecentral` | 阿联酋中部 | 使用 `uaenorth` |

**推荐的兼容区域**：
- 北美：`westus3`, `westus2`, `eastus2`
- 欧洲：`northeurope`, `westeurope`, `francecentral`
- 亚太：`japaneast`, `australiaeast`, `centralindia`

### 验证结果统计

对 Standard_D4s_v6 和 PremiumV2_LRS 的全球支持情况分析：

```bash
# 完整的统计分析脚本
echo "=== Azure 资源兼容性分析 ==="
echo ""

VM_COUNT=$(az vm list-skus --size Standard_D4s_v6 --all \
  --query "[].locationInfo[0].location" -o tsv | sort -u | wc -l)
echo "Standard_D4s_v6 支持的区域: $VM_COUNT"

DISK_COUNT=$(az vm list-skus --resource-type disks --all \
  --query "[?name=='PremiumV2_LRS'].locationInfo[0].location" -o tsv | sort -u | wc -l)
echo "PremiumV2_LRS 支持的区域: $DISK_COUNT"

echo ""
echo "结论："
echo "- Premium SSD v2 是较新的技术，覆盖范围略小"
echo "- 部署前务必运行 check-availability.sh 验证"
```
