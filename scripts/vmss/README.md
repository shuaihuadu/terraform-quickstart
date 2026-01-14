# VMSS & Disk Availability Check Script

这个脚本用于在部署前验证 Azure VMSS 和 Premium SSD v2 磁盘在指定区域和可用区的可用性，避免部署失败。

## 功能特性

- ✅ 检查 VM SKU 在指定区域的可用性
- ✅ 检查 Premium SSD v2 磁盘在指定区域的可用性  
- ✅ 验证 VM 和磁盘在同一可用区的兼容性
- ✅ 检测订阅级别的资源限制和约束
- ✅ 支持单个或多个可用区检查
- ✅ 提供清晰的错误提示和可行建议

## 使用方法

### 脚本语法

```bash
./scripts/check-vmss-disk-availability.sh <vm-sku> <region> <zones>
```

**参数说明：**
- `vm-sku`: VM SKU 名称（例如：Standard_D4s_v6）
- `region`: Azure 区域（例如：westus3）
- `zones`: 可用区，单个或逗号分隔（例如：1 或 1,2,3）

### 使用示例

```bash
# 检查单个可用区
./scripts/check-vmss-disk-availability.sh Standard_D4s_v6 westus3 3

# 检查多个可用区
./scripts/check-vmss-disk-availability.sh Standard_D4s_v6 westus3 "1,2,3"

# 测试不同的 VM 规格
./scripts/check-vmss-disk-availability.sh Standard_D8s_v6 westus3 1

# 通过 Makefile（会读取 terraform.tfvars 中的配置）
make check
```

### 通过 Makefile

Makefile 中的 `check` 目标会调用此脚本：

```bash
# 仅检查可用性
make check

# 检查并部署（自动先检查再部署）
make deploy
```

## 检查流程

脚本按以下顺序执行检查：

### 1. VM SKU 可用性检查
- 验证 VM 规格是否在目标区域可用
- 检查订阅级别的限制
- 显示 VM 支持的可用区信息

### 2. Premium SSD v2 磁盘检查
- 验证 Premium V2 磁盘是否在区域可用
- 检查磁盘在指定可用区的支持情况
- 显示磁盘支持的可用区列表

### 3. 可用区兼容性验证
- 确认 VM 和磁盘都能在同一可用区部署
- **重要**：Premium SSD v2 要求 VM 和磁盘必须在同一可用区

## 输出示例

### ✅ 检查通过（单可用区）

```
======================================
Azure Resource Availability Check
======================================

Configuration:
  VM SKU:    Standard_D4s_v6
  Region:    westus3
  Zones:     3
  Disk Type: PremiumV2_LRS

✓ Logged in to Azure
  Subscription: ME-MngEnvMCAP603028-wangch-1

1. Checking VM SKU availability in region 'westus3'...
✓ VM SKU 'Standard_D4s_v6' is available in region 'westus3'
  Available zones: [2, 3, 1]

2. Checking Disk type 'PremiumV2_LRS' in region 'westus3'...
✓ Disk type 'PremiumV2_LRS' is available in region 'westus3'
  Available zones: [1, 2, 3]

3. Checking Zone compatibility...
   Note: Premium SSD v2 requires BOTH VM and Disk in the SAME zone

  Checking zone 3...
    ✓ Zone 3: Both VM and Disk can be deployed

======================================
✅ All checks passed!

Summary:
  ✓ VM SKU 'Standard_D4s_v6' is available in region 'westus3'
  ✓ Disk 'PremiumV2_LRS' is available in region 'westus3'
  ✓ Both can be deployed in specified zones: 3

Important: Deploy VM to the same zone as Premium SSD v2
You can proceed with deployment.
======================================
```

### ❌ VM SKU 受限

```
1. Checking VM SKU availability in region 'eastus'...
❌ VM SKU has restrictions in 'eastus'
[
  {
    "reasonCode": "NotAvailableForSubscription",
    "restrictionInfo": {
      "locations": [
        "eastus"
      ]
    },
    "type": "Location",
    "values": [
      "eastus"
    ]
  }
]
```

### ❌ 区域不支持 Premium SSD v2

```
2. Checking Disk type 'PremiumV2_LRS' in region 'southindia'...
❌ Disk type 'PremiumV2_LRS' not available in region 'southindia'

💡 This region does not support Premium SSD v2
```

### ❌ VM SKU 不存在

```
1. Checking VM SKU availability in region 'westus3'...
❌ VM SKU 'Standard_D99s_v99' not found in region 'westus3'

💡 Available similar SKUs in westus3:
Standard_D2s_v5
Standard_D4s_v5
Standard_D8s_v5
Standard_D16s_v5
Standard_D32s_v5
Standard_D4s_v6
Standard_D8s_v6
Standard_D16s_v6
```

## 常见问题解决

### 问题 1: VM SKU 在区域不可用

**错误信息**：
```
❌ VM SKU 'Standard_D4s_v6' not found in region 'eastus'
```

**原因**：该 VM 规格在指定区域不存在

**解决方案**：
```bash
# 方案 1: 更换到支持的区域
# 修改 terraform.tfvars:
location = "westus3"

# 方案 2: 使用该区域支持的 VM 规格
# 脚本会列出可用的类似 SKU，从中选择一个
vm_size = "Standard_D4s_v5"
```

### 问题 2: VM SKU 有订阅级别限制

**错误信息**：
```
❌ VM SKU has restrictions in 'eastus'
[
  {
    "reasonCode": "NotAvailableForSubscription",
    ...
  }
]
```

**原因**：当前订阅没有权限在该区域使用此 VM 规格

**解决方案**：
```bash
# 方案 1: 更换区域
location = "westus3"  # 或其他无限制的区域

# 方案 2: 联系 Azure 支持申请配额
# https://portal.azure.com -> 支持 + 故障排除 -> 新建支持请求

# 方案 3: 使用不同的 VM 规格
vm_size = "Standard_D4s_v5"
```

### 问题 3: 区域不支持 Premium SSD v2

**错误信息**：
```
❌ Disk type 'PremiumV2_LRS' not available in region 'southindia'
💡 This region does not support Premium SSD v2
```

**原因**：Premium SSD v2 目前只在部分区域可用

**解决方案**：
```bash
# 方案 1: 更换到支持 Premium SSD v2 的区域
# 支持的区域包括：westus3, eastus2, northeurope, westeurope 等
location = "westus3"

# 方案 2: 使用 Premium SSD v1（修改 main.tf）
# 将 storage_account_type 从 "PremiumV2_LRS" 改为 "Premium_LRS"
# 注意：Premium v1 不支持自定义 IOPS/throughput
```

### 问题 4: 可用区不兼容

**错误信息**：
```
❌ Zone 5: Disk not supported
```

**原因**：磁盘在指定的可用区不可用

**解决方案**：
```bash
# 方案 1: 使用磁盘支持的可用区
# 脚本会显示磁盘支持的可用区列表，选择其中一个
zones = ["1"]

# 方案 2: 不使用可用区（区域级部署）
zones = null

# 方案 3: 检查多个可用区找到兼容的
./scripts/check-vmss-disk-availability.sh Standard_D4s_v6 westus3 "1,2,3"
```

### 问题 5: VM 无可用区信息

**错误信息**：
```
⚠️  VM has no zone info (can deploy to any zone)
```

**说明**：这不是错误！VM 没有可用区限制意味着可以部署到任何区域可用的可用区。只需要确保磁盘在目标可用区可用即可。

**操作**：正常继续部署

## 脚本工作原理

### 数据来源
脚本使用 Azure CLI 的 `az vm list-skus` 命令查询：
```bash
# 查询 VM SKU
az vm list-skus --location <region> --size <vm-sku>

# 查询磁盘 SKU
az vm list-skus --location <region> --resource-type disks
```

### 检查逻辑

1. **区域级检查**：首先验证资源在区域级别是否存在
2. **限制检查**：检查订阅是否有使用限制
3. **可用区检查**：验证指定的可用区是否同时支持 VM 和磁盘
4. **兼容性验证**：确保 VM 和 Premium SSD v2 可以在同一可用区部署

### 关键要求

**Premium SSD v2 的特殊要求：**
- ✅ VM 和磁盘必须在同一可用区
- ✅ 只在特定区域可用
- ✅ 需要支持 Premium Storage 的 VM 规格

## 最佳实践

### 部署前检查流程

```bash
# 1. 快速验证当前配置
./scripts/check-vmss-disk-availability.sh Standard_D4s_v6 westus3 3

# 2. 测试多个可用区
./scripts/check-vmss-disk-availability.sh Standard_D4s_v6 westus3 "1,2,3"

# 3. 确认后更新 terraform.tfvars
# 编辑文件设置：location, vm_size, zones

# 4. 通过 Makefile 部署
make deploy
```

### 推荐的区域和配置

**生产环境推荐配置：**

```hcl
# 配置 1: 美西 - 高性能
location = "westus3"
vm_size = "Standard_D4s_v6"
zones = ["3"]

# 配置 2: 美东 - 备用
location = "eastus2"  
vm_size = "Standard_D4s_v6"
zones = ["1"]

# 配置 3: 欧洲
location = "northeurope"
vm_size = "Standard_D4s_v6"
zones = ["2"]
```

## 故障排查

### 脚本无法运行

**问题**：Permission denied

**解决**：
```bash
chmod +x scripts/check-vmss-disk-availability.sh
```

### Azure CLI 未登录

**问题**：`❌ Not logged into Azure`

**解决**：
```bash
az login
# 如果有多个订阅，设置默认订阅：
az account set --subscription "subscription-name-or-id"
```

### jq 命令未找到

**问题**：脚本依赖 jq 解析 JSON

**解决**：
```bash
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq

# CentOS/RHEL
sudo yum install jq
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
## 测试用例

以下是不同场景的测试参数，可用于验证脚本的检测功能：

| 场景 | VM 支持 | PV2 支持 | Region | Zone | 预期结果 |
|------|---------|----------|--------|------|----------|
| **✅ 完全兼容** | ✅ | ✅ | `westus3` | `1` | 所有检查通过 |
| | ✅ | ✅ | `westus2` | `1` | 所有检查通过 |
| | ✅ | ✅ | `eastus2` | `2` | 所有检查通过 |
| | ✅ | ✅ | `centralus` | `1` | 所有检查通过 |
| **⚠️ 仅 VM** | ✅ | ❌ | `southindia` | `1` | PV2 不可用，提示推荐区域 |
| | ✅ | ❌ | `australiacentral` | `1` | PV2 不可用，提示推荐区域 |
| | ✅ | ❌ | `belgiumcentral` | `1` | PV2 不可用，提示推荐区域 |
| | ✅ | ❌ | `uaecentral` | `1` | PV2 不可用，提示推荐区域 |
| | ✅ | ❌ | `francesouth` | `null` | PV2 不可用，提示推荐区域 |
| | ✅ | ❌ | `germanynorth` | `null` | PV2 不可用，提示推荐区域 |
| | ✅ | ❌ | `southafricawest` | `null` | PV2 不可用，提示推荐区域 |
| **❌ VM 有限制** | ❌ | ✅ | `eastus` | `1` | VM 有订阅限制 (NotAvailableForSubscription) |
| | ❌ | ✅ | `norwayeast` | `1` | VM 不可用（ARM64 支持较晚）|

### 测试步骤

1. 修改 `terraform.tfvars` 中的配置：
   ```hcl
   location = "southindia"  # 使用上表中的 region
   zones    = ["1"]         # 使用上表中的 zone (null 表示不指定)
   ```

2. 运行检查脚本：
   ```bash
   ./scripts/check-availability.sh
   ```

3. 观察输出结果是否符合预期

### 示例测试命令

```bash
# 测试场景 1：完全兼容（应该通过）
sed -i 's/location = .*/location = "westus3"/' terraform.tfvars
sed -i 's/zones = .*/zones    = ["1"]/' terraform.tfvars
./scripts/check-availability.sh

# 测试场景 2：仅支持 VM（应该提示 PV2 不可用）
sed -i 's/location = .*/location = "southindia"/' terraform.tfvars
./scripts/check-availability.sh

# 测试场景 3：VM 有限制（应该提示 VM 订阅限制）
sed -i 's/location = .*/location = "eastus"/' terraform.tfvars
./scripts/check-availability.sh
```
