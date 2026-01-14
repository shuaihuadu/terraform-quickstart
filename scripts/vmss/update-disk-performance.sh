#!/bin/bash
# ============================================================
# Premium V2 磁盘性能更新脚本
# ============================================================
#
# 此脚本用于更新 VMSS 中 VM 所挂载的 Premium V2 数据盘的 IOPS 和吞吐量设置。
# 这是一个针对 Flexible VMSS 不支持在 data_disk 块中设置 ultra_ssd 参数的临时解决方案。
#
# 必需的环境变量：
#   RESOURCE_GROUP   - Azure 资源组名称
#   VMSS_NAME        - VMSS 名称
#   TARGET_INSTANCES - 预期的 VM 实例数量
#   TARGET_IOPS      - 目标磁盘 IOPS
#   TARGET_MBPS      - 目标磁盘吞吐量 (MB/s)
#   TARGET_LUN       - 数据盘 LUN 编号
#   POOL_NAME        - 节点池名称（用于日志）
#
# 退出码：
#   0 - 所有磁盘更新成功
#   1 - 一个或多个磁盘更新失败
#
# ============================================================

# 不使用 set -e，包含错误处理逻辑
set -o pipefail

# 配置参数
MAX_WAIT_INSTANCES=300  # 等待 VM 实例就绪的最长时间（5分钟）
MAX_WAIT_DISKS=120      # 等待磁盘附加的最长时间（2分钟）

# 全局变量（在函数间共享）
INSTANCES=""
INSTANCE_COUNT=0
TOTAL=0
SUCCESS=0
FAILED=0
SKIPPED=0
FAILED_VMS=""

# 验证必需的环境变量
validate_env() {
  local missing=0
  for var in RESOURCE_GROUP VMSS_NAME TARGET_INSTANCES TARGET_IOPS TARGET_MBPS TARGET_LUN POOL_NAME; do
    if [ -z "${!var}" ]; then
      echo "❌ 错误: 必需的环境变量 $var 未设置"
      missing=1
    fi
  done
  if [ $missing -eq 1 ]; then
    exit 1
  fi
}

# 打印头部信息
print_header() {
  echo ""
  echo "================================================================="
  echo "  更新 Premium V2 磁盘性能配置"
  echo "================================================================="
  echo ""
  echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "节点池: $POOL_NAME"
  echo "资源组: $RESOURCE_GROUP"
  echo "VMSS: $VMSS_NAME"
  echo "目标 IOPS: $TARGET_IOPS"
  echo "目标吞吐量: $TARGET_MBPS MB/s"
  echo "预期实例数: $TARGET_INSTANCES"
  echo ""
}

# 步骤 1: 等待 VM 实例就绪
# Note: Flexible VMSS uses az vm list instead of az vmss list-instances
wait_for_instances() {
  echo "=== 步骤 1: 等待 VM 实例就绪 ==="
  
  local elapsed=0
  local interval=15
  
  while [ "$elapsed" -lt "$MAX_WAIT_INSTANCES" ]; do
    # For Flexible VMSS, use az vm list filtered by VMSS prefix
    INSTANCE_COUNT=$(az vm list \
      --resource-group "$RESOURCE_GROUP" \
      --query "length([?starts_with(name, '$VMSS_NAME') && provisioningState=='Succeeded'])" -o tsv 2>/dev/null || echo "0")
    
    # 确保是数字
    INSTANCE_COUNT=${INSTANCE_COUNT:-0}
    
    echo "  [$(printf '%3d' $elapsed)s] 就绪实例: $INSTANCE_COUNT / $TARGET_INSTANCES"
    
    if [ "$INSTANCE_COUNT" -ge "$TARGET_INSTANCES" ]; then
      echo ""
      echo "  ✓ 所有 $TARGET_INSTANCES 个实例已就绪"
      return 0
    fi
    
    sleep $interval
    elapsed=$((elapsed + interval))
  done
  
  # 超时
  echo ""
  echo "  ❌ 错误: 等待 VM 实例超时"
  echo "     预期: $TARGET_INSTANCES 个实例"
  echo "     就绪: $INSTANCE_COUNT 个实例"
  echo "     等待时间: ${MAX_WAIT_INSTANCES}s"
  echo ""
  echo "  可能的原因:"
  echo "    - VM 配置时间超出预期"
  echo "    - 该区域可能存在 Azure 容量问题"
  echo "    - 请在 Azure Portal 中检查 VM 配置状态"
  echo ""
  return 1
}

# 步骤 2: 等待数据盘挂载完成
wait_for_disks() {
  echo ""
  echo "=== 步骤 2: 等待数据盘挂载完成 ==="
  
  # 获取 VM 实例列表（设置全局变量供后续使用）
  # For Flexible VMSS, use az vm list filtered by VMSS prefix
  INSTANCES=$(az vm list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?starts_with(name, '$VMSS_NAME') && provisioningState=='Succeeded'].name" -o tsv 2>/dev/null || echo "")
  
  if [ -z "$INSTANCES" ]; then
    echo ""
    echo "  ❌ 错误: 无法获取 VM 实例列表"
    return 1
  fi
  
  local elapsed=0
  local interval=10
  local disks_found=0
  
  while [ "$elapsed" -lt "$MAX_WAIT_DISKS" ]; do
    disks_found=0
    local disks_missing=0
    
    for vm_name in $INSTANCES; do
      local disk_name
      disk_name=$(az vm show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$vm_name" \
        --query "storageProfile.dataDisks[?lun==\`$TARGET_LUN\`].name" -o tsv 2>/dev/null || echo "")
      
      if [ -n "$disk_name" ]; then
        disks_found=$((disks_found + 1))
      else
        disks_missing=$((disks_missing + 1))
      fi
    done
    
    echo "  [$(printf '%3d' $elapsed)s] 已挂载磁盘: $disks_found / $TARGET_INSTANCES"
    
    if [ "$disks_found" -ge "$TARGET_INSTANCES" ]; then
      echo ""
      echo "  ✓ 所有数据盘已挂载"
      return 0
    fi
    
    sleep $interval
    elapsed=$((elapsed + interval))
  done
  
  # 超时
  echo ""
  echo "  ❌ 错误: 等待数据盘挂载超时"
  echo "     预期: 在 LUN $TARGET_LUN 上有 $TARGET_INSTANCES 个磁盘"
  echo "     找到: $disks_found 个磁盘"
  echo "     等待时间: ${MAX_WAIT_DISKS}s"
  echo ""
  return 1
}

# 步骤 3: 更新磁盘性能
update_disk_performance() {
  echo ""
  echo "=== 步骤 3: 更新磁盘性能配置 ==="
  
  for vm_name in $INSTANCES; do
    TOTAL=$((TOTAL + 1))
    echo ""
    echo "  [$TOTAL/$TARGET_INSTANCES] VM: $vm_name"
    
    # 获取磁盘名称
    local disk_name
    disk_name=$(az vm show \
      --resource-group "$RESOURCE_GROUP" \
      --name "$vm_name" \
      --query "storageProfile.dataDisks[?lun==\`$TARGET_LUN\`].name" -o tsv 2>/dev/null || echo "")
    
    if [ -z "$disk_name" ]; then
      echo "    ❌ 在 LUN $TARGET_LUN 上未找到磁盘"
      FAILED=$((FAILED + 1))
      FAILED_VMS="$FAILED_VMS $vm_name(无磁盘)"
      continue
    fi
    
    echo "    磁盘: $disk_name"
    
    # 获取当前磁盘性能
    local disk_info
    disk_info=$(az disk show \
      --resource-group "$RESOURCE_GROUP" \
      --name "$disk_name" \
      --query "{iops:diskIOPSReadWrite, mbps:diskMBpsReadWrite, sku:sku.name}" -o json 2>/dev/null || echo "")
    
    if [ -z "$disk_info" ]; then
      echo "    ❌ 无法获取磁盘信息"
      FAILED=$((FAILED + 1))
      FAILED_VMS="$FAILED_VMS $vm_name(获取信息失败)"
      continue
    fi
    
    local current_iops current_mbps current_sku
    current_iops=$(echo "$disk_info" | grep -o '"iops":[0-9]*' | cut -d':' -f2 || echo "0")
    current_mbps=$(echo "$disk_info" | grep -o '"mbps":[0-9]*' | cut -d':' -f2 || echo "0")
    current_sku=$(echo "$disk_info" | grep -o '"sku":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    
    echo "    SKU: $current_sku"
    echo "    当前: $current_iops IOPS, $current_mbps MB/s"
    echo "    目标: $TARGET_IOPS IOPS, $TARGET_MBPS MB/s"
    
    # 检查是否已经是目标值
    if [ "$current_iops" = "$TARGET_IOPS" ] && [ "$current_mbps" = "$TARGET_MBPS" ]; then
      echo "    ✓ 已是目标性能配置（跳过）"
      SKIPPED=$((SKIPPED + 1))
      SUCCESS=$((SUCCESS + 1))
      continue
    fi
    
    # 更新磁盘性能
    echo "    正在更新..."
    local update_output
    if update_output=$(az disk update \
      --resource-group "$RESOURCE_GROUP" \
      --name "$disk_name" \
      --disk-iops-read-write "$TARGET_IOPS" \
      --disk-mbps-read-write "$TARGET_MBPS" \
      --output json 2>&1); then
      
      # 验证更新结果
      local new_iops new_mbps
      new_iops=$(echo "$update_output" | grep -o '"diskIopsReadWrite":[0-9]*' | cut -d':' -f2 || echo "")
      new_mbps=$(echo "$update_output" | grep -o '"diskMBpsReadWrite":[0-9]*' | cut -d':' -f2 || echo "")
      
      if [ "$new_iops" = "$TARGET_IOPS" ] && [ "$new_mbps" = "$TARGET_MBPS" ]; then
        echo "    ✓ 更新成功: $new_iops IOPS, $new_mbps MB/s"
      else
        echo "    ✓ 更新命令已执行（验证: ${new_iops:-N/A} IOPS, ${new_mbps:-N/A} MB/s）"
      fi
      SUCCESS=$((SUCCESS + 1))
    else
      echo "    ❌ 更新失败!"
      echo "    错误: $(echo "$update_output" | head -5)"
      FAILED=$((FAILED + 1))
      FAILED_VMS="$FAILED_VMS $vm_name(更新失败)"
    fi
  done
}

# 打印汇总信息
print_summary() {
  echo ""
  echo "================================================================="
  echo "  执行汇总"
  echo "================================================================="
  echo ""
  echo "  节点池:   $POOL_NAME"
  echo "  总计:     $TOTAL 个 VM"
  echo "  成功:     $SUCCESS 个（其中 $SKIPPED 个已是目标配置）"
  echo "  失败:     $FAILED 个"
  echo ""
  echo "  完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
  
  if [ $FAILED -gt 0 ]; then
    echo "================================================================="
    echo "  ❌ 部署失败"
    echo "================================================================="
    echo ""
    echo "  $FAILED 个磁盘更新失败:"
    echo "  $FAILED_VMS"
    echo ""
    echo "  重试请运行: terraform apply"
    echo ""
    return 1
  fi
  
  echo "================================================================="
  echo "  ✓ 所有磁盘性能更新已成功完成"
  echo "================================================================="
  echo ""
  return 0
}

# 主函数
main() {
  validate_env
  print_header
  
  if ! wait_for_instances; then
    exit 1
  fi
  
  if ! wait_for_disks; then
    exit 1
  fi
  
  update_disk_performance
  
  if ! print_summary; then
    exit 1
  fi
  
  exit 0
}

# 运行主函数
main "$@"
