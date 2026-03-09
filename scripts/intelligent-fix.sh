#!/bin/bash
# 智能补丁冲突修复脚本
# 根据冲突类型自动选择修复策略

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
KERNEL_SRC="$PROJECT_ROOT/Xiaomi_Kernel_OpenSource-zijin-s-oss"
FIX_LOG="$PROJECT_ROOT/docs/CONFLICT_FIX_LOG.md"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

init_log() {
    cat > "$FIX_LOG" << EOF
# 补丁冲突修复日志

开始时间: $(date)

## 修复策略

### 自动接受Upstream的情况
1. 安全修复（Spectre, Meltdown等）
2. Bug修复
3. API改进（更安全的宏，更好的函数签名）
4. 文档更新
5. 新增功能（不影响现有代码）

### 需要评估的情况
1. API签名变化（可能影响vendor调用）
2. 结构体字段变化
3. 关键驱动修改

### 保持小米版本的情况
1. vendor特定的实现
2. 设备特定的配置
3. 性能优化代码

EOF
}

log_fix() {
    local file=$1
    local action=$2
    local reason=$3

    echo "### $file" >> "$FIX_LOG"
    echo "**动作**: $action" >> "$FIX_LOG"
    echo "**原因**: $reason" >> "$FIX_LOG"
    echo "" >> "$FIX_LOG"
}

analyze_and_fix_reject() {
    local rej_file=$1
    local target_file="${rej_file%.rej}"

    if [ ! -f "$rej_file" ]; then
        return 0
    fi

    log_step "Analyzing: $rej_file"

    local rej_content=$(cat "$rej_file")

    if echo "$rej_content" | grep -q "offsetofend"; then
        log_info "  Type: Macro improvement (offsetof -> offsetofend)"
        log_info "  Action: Accept upstream (safer macro)"
        log_fix "$rej_file" "接受upstream" "使用更安全的offsetofend宏"
        return 1
    fi

    if echo "$rej_content" | grep -q "might_sleep"; then
        log_info "  Type: API improvement (might_sleep check)"
        log_info "  Action: Accept upstream (better error checking)"
        log_fix "$rej_file" "接受upstream" "添加might_sleep检查提高可靠性"
        return 1
    fi

    if echo "$rej_content" | grep -q "GFP_ATOMIC\|GFP_KERNEL"; then
        log_info "  Type: Memory allocation API extension"
        log_info "  Action: Accept upstream (new atomic variant)"
        log_fix "$rej_file" "接受upstream" "添加atomic内存分配变体，向后兼容"
        return 1
    fi

    if echo "$rej_content" | grep -q "spectre\|SPECTRE"; then
        log_info "  Type: Security fix (Spectre)"
        log_info "  Action: Accept upstream (CRITICAL security fix)"
        log_fix "$rej_file" "接受upstream" "关键安全修复"
        return 1
    fi

    if echo "$rej_content" | grep -q "cpucaps\|cputype"; then
        log_info "  Type: CPU feature detection"
        log_info "  Action: Accept upstream (new CPU support)"
        log_fix "$rej_file" "接受upstream" "支持新CPU型号"
        return 1
    fi

    if echo "$rej_content" | grep -q "^diff.*\.h\.rej"; then
        if echo "$rej_content" | grep -q "struct\|define"; then
            log_warn "  Type: Header file structure change"
            log_warn "  Action: NEEDS MANUAL REVIEW"
            log_fix "$rej_file" "需要手动审查" "头文件结构变化，可能影响兼容性"
            return 2
        fi
    fi

    if echo "$rej_file" | grep -q "drivers/soc/qcom"; then
        log_warn "  Type: Qualcomm SOC vendor code"
        log_warn "  Action: PRESERVE XIAOMI VERSION (vendor specific)"
        log_fix "$rej_file" "保持小米版本" "Qualcomm vendor特定实现"
        echo "PRESERVE" > "${rej_file}.action"
        return 3
    fi

    log_info "  Type: General change"
    log_info "  Action: Accept upstream (default)"
    log_fix "$rej_file" "接受upstream" "默认策略"
    return 1
}

apply_upstream_patch() {
    local rej_file=$1
    local target_file="${rej_file%.rej}"

    log_step "Applying upstream patch to: $target_file"

    patch -p1 < "$rej_file" --dry-run 2>/dev/null
    if [ $? -eq 0 ]; then
        patch -p1 < "$rej_file" 2>/dev/null
        rm -f "$rej_file"
        log_info "  Successfully applied"
        return 0
    else
        log_warn "  Patch doesn't apply cleanly, manual merge needed"
        return 1
    fi
}

preserve_vendor_code() {
    local rej_file=$1
    log_step "Preserving vendor code: ${rej_file%.rej}"
    rm -f "$rej_file"
    log_info "  Reject file removed, vendor code preserved"
}

batch_fix_category() {
    local category=$1
    local dir=""

    case "$category" in
        qcom)   dir="$KERNEL_SRC/drivers/soc/qcom" ;;
        iommu)  dir="$KERNEL_SRC/drivers/iommu" ;;
        arch)   dir="$KERNEL_SRC/arch/arm64" ;;
        clk)    dir="$KERNEL_SRC/drivers/clk" ;;
        *)      log_error "Unknown category: $category"; return 1 ;;
    esac

    log_step "Processing category: $category"

    local count=0
    local auto_fixed=0
    local manual=0
    local preserved=0

    for rej_file in $(find "$dir" -name "*.rej" -type f 2>/dev/null); do
        ((count++))
        analyze_and_fix_reject "$rej_file"
        local ret=$?

        case "$ret" in
            1)
                apply_upstream_patch "$rej_file" && ((auto_fixed++))
                ;;
            2)
                ((manual++))
                ;;
            3)
                preserve_vendor_code "$rej_file" && ((preserved++))
                ;;
        esac
    done

    echo ""
    log_info "Category $category summary:"
    echo "  Total:      $count"
    echo "  Auto-fixed: $auto_fixed"
    echo "  Manual:     $manual"
    echo "  Preserved:  $preserved"
    echo ""
}

fix_all_automated() {
    log_step "Starting automated conflict resolution..."

    init_log

    batch_fix_category "qcom"
    batch_fix_category "iommu"
    batch_fix_category "arch"
    batch_fix_category "clk"

    log_step "Remaining manual fixes needed:"
    find "$KERNEL_SRC" -name "*.rej" -type f 2>/dev/null | head -20

    log_info "Fix log saved to: $FIX_LOG"
}

show_help() {
    cat << EOF
Intelligent Patch Conflict Fix Tool

Usage: $0 <command> [options]

Commands:
  fix-all          Run automated fix for all categories
  fix-qcom         Fix Qualcomm SOC conflicts
  fix-iommu        Fix IOMMU conflicts
  fix-arch         Fix architecture conflicts
  analyze          Analyze all conflicts without fixing
  help             Show this help

Examples:
  $0 fix-all
  $0 fix-qcom
  $0 analyze
EOF
}

main() {
    local action=${1:-"help"}

    case "$action" in
        fix-all)
            fix_all_automated
            ;;
        fix-qcom)
            init_log
            batch_fix_category "qcom"
            ;;
        fix-iommu)
            init_log
            batch_fix_category "iommu"
            ;;
        fix-arch)
            init_log
            batch_fix_category "arch"
            ;;
        analyze)
            init_log
            for rej in $(find "$KERNEL_SRC" -name "*.rej" -type f 2>/dev/null | head -20); do
                analyze_and_fix_reject "$rej"
                echo ""
            done
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $action"
            show_help
            exit 1
            ;;
    esac
}

main "$@"