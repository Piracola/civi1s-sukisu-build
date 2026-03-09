#!/bin/bash
# 增量更新和冲突手动解决脚本
# 每次更新10个版本，手动处理每个冲突

set -e

SCRIPT_DIR="/home/cola/civi1s-sukisu-build/scripts"
KERNEL_SRC="/home/cola/civi1s-sukisu-build/Xiaomi_Kernel_OpenSource-zijin-s-oss"
VERSION_FILE="/home/cola/civi1s-sukisu-build/KERNEL_VERSION"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_manual() { echo -e "${CYAN}[MANUAL]${NC} $1"; }

get_current_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE"
    else
        cd "$KERNEL_SRC"
        grep "^SUBLEVEL = " Makefile | awk '{print $3}'
    fi
}

download_patch() {
    local from_version=$1
    local to_version=$2
    local patch_file="/tmp/patch-${to_version}.xz"

    local major=5
    local minor=4
    local from_sub=$(echo "$from_version" | cut -d. -f3)
    local to_sub=$(echo "$to_version" | cut -d. -f3)

    local url="https://cdn.kernel.org/pub/linux/kernel/v5.x/incr/patch-${major}.${minor}.${from_sub}-${to_sub}.xz"

    log_step "Downloading: patch-${major}.${minor}.${from_sub}-${to_sub}.xz"

    curl -L --progress-bar "$url" -o "$patch_file" || {
        log_error "Failed to download patch"
        return 1
    }

    xz -d -f "$patch_file" || {
        log_error "Failed to decompress patch"
        return 1
    }

    echo "${patch_file%.xz}"
}

apply_patch_manual() {
    local patch_file=$1
    local version=$2

    cd "$KERNEL_SRC"

    log_step "Applying patch for version $version"
    log_info "Patch file: $patch_file"

    if git apply --check "$patch_file" 2>/dev/null; then
        log_info "Patch applies cleanly!"
        git apply "$patch_file"
        return 0
    else
        log_warn "Patch has conflicts!"
        log_manual "Manual resolution required"

        echo ""
        echo "========================================="
        echo "手动解决步骤："
        echo "========================================="
        echo ""
        echo "1. 查看reject文件内容："
        echo "   find . -name '*.rej' -exec cat {} \\;"
        echo ""
        echo "2. 查看具体冲突："
        echo "   git apply --reject --whitespace=fix $patch_file"
        echo ""
        echo "3. 手动编辑冲突文件："
        echo "   vim <conflicted-file>"
        echo ""
        echo "4. 解决后清理reject文件："
        echo "   find . -name '*.rej' -delete"
        echo ""
        echo "5. 更新版本号："
        echo "   sed -i 's/SUBLEVEL = .*/SUBLEVEL = $version/' Makefile"
        echo ""
        echo "按Enter继续手动解决..."
        read

        git apply --reject --whitespace=fix "$patch_file" 2>/dev/null || true

        local rej_count=$(find . -name "*.rej" 2>/dev/null | wc -l)

        if [ "$rej_count" -gt 0 ]; then
            log_warn "Found $rej_count reject files"
            log_manual "Please resolve conflicts manually"
            echo ""
            echo "Reject files:"
            find . -name "*.rej" 2>/dev/null | head -10
            echo ""
            echo "解决完冲突后，按Enter继续..."
            read
        fi

        return 1
    fi
}

incremental_update() {
    local start_version=$1
    local step=${2:-10}

    local current_sub=$(echo "$start_version" | cut -d. -f3)
    local target_sub=$((current_sub + step))

    log_info "========================================="
    log_info "增量更新: 5.4.$current_sub → 5.4.$target_sub"
    log_info "========================================="
    echo ""

    local current=$current_sub
    local applied=0
    local failed=0

    while [ "$current" -lt "$target_sub" ]; do
        local next=$((current + 1))
        local current_ver="5.4.$current"
        local next_ver="5.4.$next"

        echo ""
        log_step "Updating: $current_ver → $next_ver"

        local patch_file=$(download_patch "$current_ver" "$next_ver")

        if [ -n "$patch_file" ]; then
            if apply_patch_manual "$patch_file" "$next"; then
                ((applied++))
                sed -i "s/^SUBLEVEL = .*/SUBLEVEL = $next/" "$KERNEL_SRC/Makefile"
            else
                ((failed++))
                log_warn "Patch $next_ver needs manual resolution"
            fi

            rm -f "$patch_file"
        else
            ((failed++))
            log_error "Failed to download patch for $next_ver"
        fi

        current=$next
    done

    echo ""
    log_info "本轮更新完成："
    echo "  成功应用: $applied"
    echo "  需要手动解决: $failed"

    if [ $failed -gt 0 ]; then
        log_warn "请手动解决冲突后再继续下一轮更新"
    fi

    echo "$next_ver" > "$VERSION_FILE"
}

interactive_mode() {
    local current=$(get_current_version)

    echo ""
    log_info "当前内核版本: $current"
    log_info "目标版本: 5.4.302"
    echo ""

    log_info "增量更新计划："
    echo "  每轮更新: 10个版本"
    echo "  总轮数: 约15轮"
    echo "  预计耗时: 2-3小时"
    echo ""

    log_manual "准备好了吗？按Enter开始第一轮更新..."
    read

    local current_sub=$(echo "$current" | cut -d. -f3)

    while [ "$current_sub" -lt 302 ]; do
        incremental_update "5.4.$current_sub" 10

        log_manual "本轮完成。继续下一轮？(y/n)"
        read -n 1 -r
        echo

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "更新暂停。当前版本: $(get_current_version)"
            log_info "可以稍后继续运行此脚本"
            break
        fi

        current_sub=$((current_sub + 10))
    done

    if [ "$current_sub" -ge 302 ]; then
        log_info "========================================="
        log_info "🎉 更新完成！"
        log_info "========================================="
        log_info "最终版本: $(get_current_version)"
    fi
}

show_help() {
    cat << EOF
增量更新和手动冲突解决工具

用法: $0 <命令> [选项]

命令:
  start               开始交互式增量更新
  update [step]       执行一轮增量更新（默认10个版本）
  version             显示当前版本
  help                显示帮助信息

示例:
  $0 start            # 开始交互式更新
  $0 update 10        # 更新10个版本
  $0 update 5         # 更新5个版本
EOF
}

main() {
    local action=${1:-"help"}

    case "$action" in
        start)
            interactive_mode
            ;;
        update)
            local step=${2:-10}
            local current=$(get_current_version)
            incremental_update "$current" "$step"
            ;;
        version)
            get_current_version
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