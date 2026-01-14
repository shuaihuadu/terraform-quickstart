#!/bin/bash
# ============================================================
# VMSS 手动扩容脚本（带磁盘性能更新）
# ============================================================
#
# 此脚本用于手动扩容 Flexible VMSS 并自动更新新磁盘的 IOPS/吞吐量。
# 完全独立运行，不依赖 Terraform 配置文件。
#
# 用法:
#   ./scale-vmss.sh -g <resource-group> -n <vmss-name> -c <instance-count> [options]
#
# 示例:
#   # 扩容到 4 个实例，使用默认磁盘性能
#   ./scale-vmss.sh -g rg-vmss-pdv2 -n vmss-pdv2-demo -c 4
#
#   # 扩容并指定磁盘性能
#   ./scale-vmss.sh -g rg-vmss-pdv2 -n vmss-pdv2-demo -c 4 --iops 16000 --mbps 1000
#
#   # 仅更新现有磁盘性能（不扩容）
#   ./scale-vmss.sh -g rg-vmss-pdv2 -n vmss-pdv2-demo --update-only --iops 16000 --mbps 1000
#
# ============================================================

set -o pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 默认配置
DEFAULT_LUN=0
MAX_WAIT_INSTANCES=300
MAX_WAIT_DISKS=120

# 全局变量
RESOURCE_GROUP=""
VMSS_NAME=""
TARGET_COUNT=""
TARGET_IOPS=""
TARGET_MBPS=""
TARGET_LUN=$DEFAULT_LUN
UPDATE_ONLY=false
DRY_RUN=false
CURRENT_COUNT=0

# 显示帮助信息
show_usage() {
    cat << EOF
VMSS 手动扩容脚本（带磁盘性能更新）

用法:
  $0 -g <resource-group> -n <vmss-name> -c <instance-count> [options]
  $0 -g <resource-group> -n <vmss-name> --update-only [options]

必需参数:
  -g, --resource-group    Azure 资源组名称
  -n, --vmss-name         VMSS 名称

扩容参数:
  -c, --count             目标实例数量

磁盘性能参数:
  --iops                  目标 IOPS（如 16000）
  --mbps                  目标吞吐量 MB/s（如 1000）
  --lun                   数据盘 LUN 编号（默认: 0）

模式选项:
  --update-only           仅更新现有磁盘性能，不扩容
  --dry-run               模拟运行，不执行实际操作

其他选项:
  -h, --help              显示此帮助信息

示例:
  # 扩容到 4 个实例
  $0 -g rg-vmss-pdv2 -n vmss-pdv2-demo -c 4

  # 扩容并设置磁盘性能
  $0 -g rg-vmss-pdv2 -n vmss-pdv2-demo -c 4 --iops 16000 --mbps 1000

  # 仅更新所有现有磁盘的性能
  $0 -g rg-vmss-pdv2 -n vmss-pdv2-demo --update-only --iops 16000 --mbps 1000

  # 模拟扩容（不执行）
  $0 -g rg-vmss-pdv2 -n vmss-pdv2-demo -c 4 --dry-run

EOF
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -n|--vmss-name)
                VMSS_NAME="$2"
                shift 2
                ;;
            -c|--count)
                TARGET_COUNT="$2"
                shift 2
                ;;
            --iops)
                TARGET_IOPS="$2"
                shift 2
                ;;
            --mbps)
                TARGET_MBPS="$2"
                shift 2
                ;;
            --lun)
                TARGET_LUN="$2"
                shift 2
                ;;
            --update-only)
                UPDATE_ONLY=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo -e "${RED}❌ 未知参数: $1${NC}"
                echo ""
                show_usage
                exit 1
                ;;
        esac
    done
}

# 验证参数
validate_args() {
    local errors=0

    if [ -z "$RESOURCE_GROUP" ]; then
        echo -e "${RED}❌ 错误: 必须指定资源组 (-g)${NC}"
        errors=1
    fi

    if [ -z "$VMSS_NAME" ]; then
        echo -e "${RED}❌ 错误: 必须指定 VMSS 名称 (-n)${NC}"
        errors=1
    fi

    if [ "$UPDATE_ONLY" = false ] && [ -z "$TARGET_COUNT" ]; then
        echo -e "${RED}❌ 错误: 必须指定目标实例数 (-c) 或使用 --update-only${NC}"
        errors=1
    fi

    if [ -n "$TARGET_IOPS" ] && [ -z "$TARGET_MBPS" ]; then
        echo -e "${RED}❌ 错误: 指定 --iops 时必须同时指定 --mbps${NC}"
        errors=1
    fi

    if [ -z "$TARGET_IOPS" ] && [ -n "$TARGET_MBPS" ]; then
        echo -e "${RED}❌ 错误: 指定 --mbps 时必须同时指定 --iops${NC}"
        errors=1
    fi

    if [ $errors -eq 1 ]; then
        echo ""
        show_usage
        exit 1
    fi
}

# 打印头部信息
print_header() {
    echo ""
    echo -e "${BLUE}=================================================================${NC}"
    echo -e "${BLUE}  VMSS 手动扩容脚本${NC}"
    echo -e "${BLUE}=================================================================${NC}"
    echo ""
    echo -e "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "资源组: ${CYAN}$RESOURCE_GROUP${NC}"
    echo -e "VMSS: ${CYAN}$VMSS_NAME${NC}"
    
    if [ "$UPDATE_ONLY" = true ]; then
        echo -e "模式: ${YELLOW}仅更新磁盘性能${NC}"
    else
        echo -e "目标实例数: ${CYAN}$TARGET_COUNT${NC}"
    fi
    
    if [ -n "$TARGET_IOPS" ]; then
        echo -e "目标 IOPS: ${CYAN}$TARGET_IOPS${NC}"
        echo -e "目标吞吐量: ${CYAN}$TARGET_MBPS MB/s${NC}"
        echo -e "数据盘 LUN: ${CYAN}$TARGET_LUN${NC}"
    else
        echo -e "磁盘性能: ${YELLOW}不更新${NC}"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}⚠️  模拟运行模式 - 不执行实际操作${NC}"
    fi
    echo ""
}

# 检查 VMSS 是否存在
check_vmss_exists() {
    echo -e "${BLUE}=== 检查 VMSS ===${NC}"
    
    local vmss_info
    vmss_info=$(az vmss show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VMSS_NAME" \
        --query "{sku:sku.name, capacity:sku.capacity, mode:orchestrationMode}" \
        -o json 2>/dev/null)
    
    if [ -z "$vmss_info" ] || [ "$vmss_info" = "null" ]; then
        echo -e "${RED}❌ VMSS '$VMSS_NAME' 不存在于资源组 '$RESOURCE_GROUP'${NC}"
        exit 1
    fi
    
    CURRENT_COUNT=$(echo "$vmss_info" | jq -r '.capacity')
    local sku_name=$(echo "$vmss_info" | jq -r '.sku')
    local mode=$(echo "$vmss_info" | jq -r '.mode')
    
    echo -e "  ✓ VMSS 存在"
    echo -e "    SKU: $sku_name"
    echo -e "    编排模式: $mode"
    echo -e "    当前实例数: ${CYAN}$CURRENT_COUNT${NC}"
    
    if [ "$mode" != "Flexible" ]; then
        echo -e "${YELLOW}⚠️  注意: 此脚本针对 Flexible VMSS 优化${NC}"
    fi
    echo ""
}

# 扩容 VMSS
scale_vmss() {
    if [ "$UPDATE_ONLY" = true ]; then
        echo -e "${BLUE}=== 跳过扩容（仅更新模式）===${NC}"
        return 0
    fi
    
    echo -e "${BLUE}=== 步骤 1: 扩容 VMSS ===${NC}"
    
    if [ "$CURRENT_COUNT" -eq "$TARGET_COUNT" ]; then
        echo -e "  ${YELLOW}⚠️  当前实例数 ($CURRENT_COUNT) 已等于目标数 ($TARGET_COUNT)${NC}"
        echo -e "  跳过扩容步骤"
        return 0
    fi
    
    if [ "$CURRENT_COUNT" -gt "$TARGET_COUNT" ]; then
        echo -e "  ${YELLOW}⚠️  当前实例数 ($CURRENT_COUNT) 大于目标数 ($TARGET_COUNT)${NC}"
        echo -e "  这将缩减实例"
    fi
    
    echo -e "  扩容: $CURRENT_COUNT → $TARGET_COUNT"
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}[DRY-RUN] 跳过: az vmss scale ...${NC}"
        return 0
    fi
    
    if az vmss scale \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VMSS_NAME" \
        --new-capacity "$TARGET_COUNT" \
        --output none 2>&1; then
        echo -e "  ${GREEN}✓ 扩容命令已执行${NC}"
    else
        echo -e "  ${RED}❌ 扩容失败${NC}"
        exit 1
    fi
    echo ""
}

# 等待 VM 实例就绪
wait_for_instances() {
    local expected_count=${1:-$TARGET_COUNT}
    
    if [ "$UPDATE_ONLY" = true ]; then
        expected_count=$CURRENT_COUNT
    fi
    
    echo -e "${BLUE}=== 步骤 2: 等待 VM 实例就绪 ===${NC}"
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}[DRY-RUN] 跳过等待${NC}"
        return 0
    fi
    
    local elapsed=0
    local interval=15
    
    while [ "$elapsed" -lt "$MAX_WAIT_INSTANCES" ]; do
        # Flexible VMSS 使用 az vm list
        local ready_count
        ready_count=$(az vm list \
            --resource-group "$RESOURCE_GROUP" \
            --query "length([?starts_with(name, '$VMSS_NAME') && provisioningState=='Succeeded'])" \
            -o tsv 2>/dev/null || echo "0")
        
        ready_count=${ready_count:-0}
        
        echo -e "  [$(printf '%3d' $elapsed)s] 就绪实例: $ready_count / $expected_count"
        
        if [ "$ready_count" -ge "$expected_count" ]; then
            echo ""
            echo -e "  ${GREEN}✓ 所有 $expected_count 个实例已就绪${NC}"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo ""
    echo -e "  ${RED}❌ 等待 VM 实例超时${NC}"
    echo -e "     预期: $expected_count 个实例"
    echo -e "     等待时间: ${MAX_WAIT_INSTANCES}s"
    return 1
}

# 更新磁盘性能
update_disk_performance() {
    if [ -z "$TARGET_IOPS" ]; then
        echo -e "${BLUE}=== 跳过磁盘性能更新（未指定 IOPS/MBPS）===${NC}"
        return 0
    fi
    
    echo ""
    echo -e "${BLUE}=== 步骤 3: 更新磁盘性能配置 ===${NC}"
    
    # 获取所有 VM 实例
    local instances
    instances=$(az vm list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?starts_with(name, '$VMSS_NAME') && provisioningState=='Succeeded'].name" \
        -o tsv 2>/dev/null || echo "")
    
    if [ -z "$instances" ]; then
        echo -e "  ${RED}❌ 无法获取 VM 实例列表${NC}"
        return 1
    fi
    
    local total=0
    local success=0
    local skipped=0
    local failed=0
    
    for vm_name in $instances; do
        total=$((total + 1))
        echo ""
        echo -e "  [$total] VM: ${CYAN}$vm_name${NC}"
        
        # 获取磁盘名称
        local disk_name
        disk_name=$(az vm show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$vm_name" \
            --query "storageProfile.dataDisks[?lun==\`$TARGET_LUN\`].name" \
            -o tsv 2>/dev/null || echo "")
        
        if [ -z "$disk_name" ]; then
            echo -e "      ${YELLOW}⚠️  未找到 LUN $TARGET_LUN 上的数据盘（跳过）${NC}"
            skipped=$((skipped + 1))
            continue
        fi
        
        echo -e "      磁盘: $disk_name"
        
        # 获取当前性能
        local disk_info
        disk_info=$(az disk show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$disk_name" \
            --query "{iops:diskIOPSReadWrite, mbps:diskMBpsReadWrite, sku:sku.name}" \
            -o json 2>/dev/null || echo "{}")
        
        local current_iops=$(echo "$disk_info" | jq -r '.iops // 0')
        local current_mbps=$(echo "$disk_info" | jq -r '.mbps // 0')
        local current_sku=$(echo "$disk_info" | jq -r '.sku // "unknown"')
        
        echo -e "      SKU: $current_sku"
        echo -e "      当前: $current_iops IOPS, $current_mbps MB/s"
        echo -e "      目标: $TARGET_IOPS IOPS, $TARGET_MBPS MB/s"
        
        # 检查是否需要更新
        if [ "$current_iops" = "$TARGET_IOPS" ] && [ "$current_mbps" = "$TARGET_MBPS" ]; then
            echo -e "      ${GREEN}✓ 已是目标配置（跳过）${NC}"
            skipped=$((skipped + 1))
            success=$((success + 1))
            continue
        fi
        
        if [ "$DRY_RUN" = true ]; then
            echo -e "      ${YELLOW}[DRY-RUN] 跳过: az disk update ...${NC}"
            success=$((success + 1))
            continue
        fi
        
        # 更新磁盘
        echo -e "      正在更新..."
        if az disk update \
            --resource-group "$RESOURCE_GROUP" \
            --name "$disk_name" \
            --disk-iops-read-write "$TARGET_IOPS" \
            --disk-mbps-read-write "$TARGET_MBPS" \
            --output none 2>&1; then
            
            # 验证更新
            local new_info
            new_info=$(az disk show \
                --resource-group "$RESOURCE_GROUP" \
                --name "$disk_name" \
                --query "{iops:diskIOPSReadWrite, mbps:diskMBpsReadWrite}" \
                -o json 2>/dev/null || echo "{}")
            
            local new_iops=$(echo "$new_info" | jq -r '.iops // 0')
            local new_mbps=$(echo "$new_info" | jq -r '.mbps // 0')
            
            echo -e "      ${GREEN}✓ 更新成功: $new_iops IOPS, $new_mbps MB/s${NC}"
            success=$((success + 1))
        else
            echo -e "      ${RED}❌ 更新失败${NC}"
            failed=$((failed + 1))
        fi
    done
    
    echo ""
    echo -e "${BLUE}磁盘更新汇总:${NC}"
    echo -e "  总计: $total 个磁盘"
    echo -e "  成功: $success 个（其中 $skipped 个已是目标配置）"
    echo -e "  失败: $failed 个"
    
    if [ $failed -gt 0 ]; then
        return 1
    fi
    return 0
}

# 打印最终汇总
print_summary() {
    local exit_code=$1
    
    echo ""
    echo -e "${BLUE}=================================================================${NC}"
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}  ✓ 操作完成${NC}"
    else
        echo -e "${RED}  ❌ 操作失败${NC}"
    fi
    
    echo -e "${BLUE}=================================================================${NC}"
    echo ""
    echo -e "完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 显示当前状态
    if [ "$DRY_RUN" = false ]; then
        echo ""
        echo -e "${BLUE}当前 VMSS 状态:${NC}"
        az vmss show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VMSS_NAME" \
            --query "{name:name, capacity:sku.capacity, sku:sku.name}" \
            -o table 2>/dev/null || true
        
        if [ -n "$TARGET_IOPS" ]; then
            echo ""
            echo -e "${BLUE}磁盘性能状态:${NC}"
            az disk list \
                --resource-group "$RESOURCE_GROUP" \
                --query "[?contains(name, '$VMSS_NAME')].{Name:name, SKU:sku.name, IOPS:diskIOPSReadWrite, MBPS:diskMBpsReadWrite}" \
                -o table 2>/dev/null || true
        fi
    fi
    
    echo ""
}

# 主函数
main() {
    parse_args "$@"
    validate_args
    print_header
    
    # 检查 Azure CLI
    if ! command -v az &> /dev/null; then
        echo -e "${RED}❌ Azure CLI 未安装${NC}"
        exit 1
    fi
    
    if ! az account show &> /dev/null; then
        echo -e "${RED}❌ 未登录 Azure，请先运行: az login${NC}"
        exit 1
    fi
    
    check_vmss_exists
    
    local result=0
    
    if [ "$UPDATE_ONLY" = false ]; then
        scale_vmss || result=1
    fi
    
    if [ $result -eq 0 ]; then
        wait_for_instances || result=1
    fi
    
    if [ $result -eq 0 ] && [ -n "$TARGET_IOPS" ]; then
        update_disk_performance || result=1
    fi
    
    print_summary $result
    exit $result
}

# 运行
main "$@"
