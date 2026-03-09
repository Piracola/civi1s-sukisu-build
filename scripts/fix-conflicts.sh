#!/bin/bash
# 补丁冲突分析和修复工具

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
KERNEL_SRC="$PROJECT_ROOT/Xiaomi_Kernel_OpenSource-zijin-s-oss"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

analyze_conflicts() {
    log_step "Analyzing patch conflicts..."
    
    local total_rej=$(find "$KERNEL_SRC" -name "*.rej" 2>/dev/null | wc -l)
    
    echo ""
    echo "=== Conflict Summary ==="
    echo "Total reject files: $total_rej"
    echo ""
    
    echo "High Priority Conflicts:"
    echo "  drivers/soc/qcom/: $(find "$KERNEL_SRC/drivers/soc/qcom" -name "*.rej" 2>/dev/null | wc -l) files"
    echo "  drivers/iommu/:    $(find "$KERNEL_SRC/drivers/iommu" -name "*.rej" 2>/dev/null | wc -l) files"
    echo "  arch/arm64/:       $(find "$KERNEL_SRC/arch/arm64" -name "*.rej" 2>/dev/null | wc -l) files"
    echo ""
    
    echo "Medium Priority Conflicts:"
    echo "  drivers/clk/:      $(find "$KERNEL_SRC/drivers/clk" -name "*.rej" 2>/dev/null | wc -l) files"
    echo "  drivers/gpio/:     $(find "$KERNEL_SRC/drivers/gpio" -name "*.rej" 2>/dev/null | wc -l) files"
    echo "  drivers/pinctrl/:  $(find "$KERNEL_SRC/drivers/pinctrl" -name "*.rej" 2>/dev/null | wc -l) files"
    echo ""
    
    echo "Low Priority Conflicts:"
    echo "  Other files:       $((total_rej - $(find "$KERNEL_SRC/drivers/soc/qcom" -name "*.rej" 2>/dev/null | wc -l) - $(find "$KERNEL_SRC/drivers/iommu" -name "*.rej" 2>/dev/null | wc -l) - $(find "$KERNEL_SRC/arch/arm64" -name "*.rej" 2>/dev/null | wc -l))) files"
}

show_reject_file() {
    local rej_file=$1
    
    if [ ! -f "$rej_file" ]; then
        log_error "Reject file not found: $rej_file"
        return 1
    fi
    
    echo ""
    echo "=== $rej_file ==="
    echo ""
    cat "$rej_file"
    echo ""
}

clean_reject_files() {
    log_step "Cleaning reject files..."
    
    local count=$(find "$KERNEL_SRC" -name "*.rej" 2>/dev/null | wc -l)
    
    if [ "$count" -eq 0 ]; then
        log_info "No reject files found"
        return 0
    fi
    
    log_warn "Found $count reject files"
    read -p "Delete all reject files? [y/N] " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        find "$KERNEL_SRC" -name "*.rej" -type f -delete
        log_info "Deleted $count reject files"
    else
        log_info "Cancelled"
    fi
}

manual_merge_guide() {
    local rej_file=$1
    local target_file="${rej_file%.rej}"
    
    echo ""
    echo "=== Manual Merge Guide ==="
    echo ""
    echo "Reject file: $rej_file"
    echo "Target file: $target_file"
    echo ""
    echo "Steps:"
    echo "1. Open both files:"
    echo "   vim -d $target_file $rej_file"
    echo ""
    echo "2. Analyze the conflict in .rej file"
    echo "   - Lines starting with '---' show old content"
    echo "   - Lines starting with '+++' show new content"
    echo ""
    echo "3. Decide which version to keep:"
    echo "   - Upstream (5.4.302): Usually safer, has latest fixes"
    echo "   - Xiaomi vendor: May have device-specific modifications"
    echo ""
    echo "4. Apply changes manually to $target_file"
    echo ""
    echo "5. Delete the .rej file:"
    echo "   rm $rej_file"
    echo ""
}

fix_specific_file() {
    local rej_file=$1
    
    if [ ! -f "$rej_file" ]; then
        log_error "File not found: $rej_file"
        return 1
    fi
    
    show_reject_file "$rej_file"
    manual_merge_guide "$rej_file"
    
    echo "After manual merge, press Enter to continue..."
    read
}

batch_fix_category() {
    local category=$1
    
    case "$category" in
        qcom)
            log_step "Fixing Qualcomm SOC conflicts..."
            find "$KERNEL_SRC/drivers/soc/qcom" -name "*.rej" -type f
            ;;
        iommu)
            log_step "Fixing IOMMU conflicts..."
            find "$KERNEL_SRC/drivers/iommu" -name "*.rej" -type f
            ;;
        arch)
            log_step "Fixing architecture conflicts..."
            find "$KERNEL_SRC/arch/arm64" -name "*.rej" -type f
            ;;
        *)
            log_error "Unknown category: $category"
            return 1
            ;;
    esac
}

generate_report() {
    local report_file="$PROJECT_ROOT/docs/CONFLICT_FIX_REPORT.md"
    
    log_step "Generating conflict fix report..."
    
    cat > "$report_file" << EOF
# 补丁冲突修复报告

生成时间: $(date)

## 概述

本文档记录从 Linux 5.4.150 更新到 5.4.302 过程中的补丁冲突修复过程。

## 冲突统计

$(cd "$KERNEL_SRC" && find . -name "*.rej" 2>/dev/null | wc -l) 个 reject 文件待处理

### 高优先级冲突

#### Qualcomm SOC (drivers/soc/qcom/)
$(cd "$KERNEL_SRC" && find drivers/soc/qcom -name "*.rej" 2>/dev/null | sed 's/^/- /')

#### IOMMU (drivers/iommu/)
$(cd "$KERNEL_SRC" && find drivers/iommu -name "*.rej" 2>/dev/null | sed 's/^/- /')

#### Architecture (arch/arm64/)
$(cd "$KERNEL_SRC" && find arch/arm64 -name "*.rej" 2>/dev/null | sed 's/^/- /')

## 修复策略

### 决策原则

1. **API兼容性优先**: 保持与小米vendor代码的兼容
2. **安全补丁必须**: 安全相关补丁必须应用
3. **功能补丁评估**: 根据实际需求决定是否应用
4. **文档补丁可选**: 文档注释可以接受upstream版本

### 修复方法

1. 分析reject文件内容
2. 理解冲突原因
3. 决定保留哪个版本
4. 手动应用修改
5. 删除reject文件
6. 测试编译

## 修复记录

EOF
    
    log_info "Report generated: $report_file"
}

show_help() {
    cat << EOF
Patch Conflict Analysis and Fix Tool

Usage: $0 <command> [options]

Commands:
  analyze              Analyze all conflicts (default)
  show <file.rej>      Show specific reject file content
  fix <file.rej>       Interactive fix for specific file
  clean                Delete all reject files
  category <name>      List files in category (qcom/iommu/arch)
  report               Generate conflict fix report
  help                 Show this help message

Examples:
  $0 analyze
  $0 show drivers/soc/qcom/socinfo.c.rej
  $0 fix drivers/iommu/iommu.c.rej
  $0 clean
  $0 category qcom
  $0 report
EOF
}

main() {
    local action=${1:-"analyze"}
    
    case "$action" in
        analyze)
            analyze_conflicts
            ;;
        show)
            show_reject_file "$2"
            ;;
        fix)
            fix_specific_file "$2"
            ;;
        clean)
            clean_reject_files
            ;;
        category)
            batch_fix_category "$2"
            ;;
        report)
            generate_report
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