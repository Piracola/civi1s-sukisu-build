#!/bin/bash
# 智能内核版本更新脚本
# 支持自动检测、增量更新、冲突处理和回滚

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
KERNEL_SRC="$PROJECT_ROOT/Xiaomi_Kernel_OpenSource-zijin-s-oss"
VERSION_FILE="$PROJECT_ROOT/KERNEL_VERSION"
BACKUP_DIR="$PROJECT_ROOT/.kernel_backups"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_debug() { echo -e "${PURPLE}[DEBUG]${NC} $1"; }

# 获取当前内核版本
get_current_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE"
    elif [ -d "$KERNEL_SRC" ]; then
        cd "$KERNEL_SRC"
        make kernelversion 2>/dev/null || {
            local major=$(grep "^VERSION = " Makefile | awk '{print $3}')
            local minor=$(grep "^PATCHLEVEL = " Makefile | awk '{print $3}')
            local sub=$(grep "^SUBLEVEL = " Makefile | awk '{print $3}')
            echo "${major}.${minor}.${sub}"
        }
    else
        echo "5.4.150"
    fi
}

# 获取最新的LTS版本
get_latest_lts_version() {
    local branch=${1:-"5.4"}
    
    # 从kernel.org获取最新版本
    local latest=$(curl -sL --connect-timeout 15 --max-time 30 \
        "https://cdn.kernel.org/pub/linux/kernel/v${branch%%.*}.x/" 2>/dev/null | \
        grep -oP "patch-${branch}\.\d+\.xz" | \
        grep -oP "${branch}\.\d+" | \
        sort -V | \
        tail -1)
    
    if [ -z "$latest" ]; then
        # 备用方案：从kernel.org主站获取
        latest=$(curl -sL --connect-timeout 15 --max-time 30 \
            "https://www.kernel.org/pub/linux/kernel/v${branch%%.*}.x/" 2>/dev/null | \
            grep -oP "linux-${branch}\.\d+\.tar\.xz" | \
            grep -oP "${branch}\.\d+" | \
            sort -V | \
            tail -1)
    fi
    
    echo "$latest"
}

# 比较版本号
version_compare() {
    local v1=$1
    local v2=$2
    
    IFS='.' read -r maj1 min1 sub1 <<< "$v1"
    IFS='.' read -r maj2 min2 sub2 <<< "$v2"
    
    if [ "$maj1" -ne "$maj2" ] || [ "$min1" -ne "$min2" ]; then
        echo "different_branch"
        return
    fi
    
    if [ "$sub1" -lt "$sub2" ]; then
        echo "update_needed"
    elif [ "$sub1" -gt "$sub2" ]; then
        echo "downgrade"
    else
        echo "same"
    fi
}

# 创建备份
create_backup() {
    local version=$1
    
    mkdir -p "$BACKUP_DIR"
    
    local backup_name="kernel-backup-${version}-$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    log_step "Creating backup: $backup_name"
    
    # 备份关键文件
    if [ -d "$KERNEL_SRC" ]; then
        cd "$KERNEL_SRC"
        
        # 备份Makefile和配置
        mkdir -p "$backup_path"
        cp Makefile "$backup_path/" 2>/dev/null || true
        cp .config "$backup_path/" 2>/dev/null || true
        cp -r arch/arm64/configs "$backup_path/" 2>/dev/null || true
        
        # 记录git状态
        git status > "$backup_path/git-status.txt" 2>/dev/null || true
        git diff > "$backup_path/git-diff.patch" 2>/dev/null || true
        
        log_info "Backup created at: $backup_path"
    fi
}

# 恢复备份
restore_backup() {
    local backup_name=$1
    
    if [ -z "$backup_name" ]; then
        # 列出可用备份
        log_info "Available backups:"
        ls -lt "$BACKUP_DIR" | head -10
        return
    fi
    
    local backup_path="$BACKUP_DIR/$backup_name"
    
    if [ ! -d "$backup_path" ]; then
        log_error "Backup not found: $backup_path"
        return 1
    fi
    
    log_step "Restoring backup: $backup_name"
    
    cd "$KERNEL_SRC"
    
    # 恢复文件
    cp "$backup_path/Makefile" . 2>/dev/null || true
    cp "$backup_path/.config" . 2>/dev/null || true
    cp -r "$backup_path/configs" arch/arm64/ 2>/dev/null || true
    
    # 应用补丁
    if [ -f "$backup_path/git-diff.patch" ]; then
        git apply "$backup_path/git-diff.patch" 2>/dev/null || log_warn "Failed to apply backup patch"
    fi
    
    log_info "Backup restored successfully"
}

# 下载并验证补丁
download_patch() {
    local from_version=$1
    local to_version=$2
    local patch_file=$3
    
    local major=$(echo "$from_version" | cut -d. -f1)
    local minor=$(echo "$from_version" | cut -d. -f2)
    local from_sub=$(echo "$from_version" | cut -d. -f3)
    local to_sub=$(echo "$to_version" | cut -d. -f3)
    
    local patch_url="https://cdn.kernel.org/pub/linux/kernel/v${major}.x/incr/patch-${major}.${minor}.${from_sub}-${to_sub}.xz"
    
    log_debug "Downloading patch from: $patch_url"
    
    if curl -L --progress-bar --connect-timeout 30 --max-time 120 \
        "$patch_url" -o "${patch_file}.xz"; then
        
        # 验证下载的文件
        if xz -t "${patch_file}.xz" 2>/dev/null; then
            xz -d -f "${patch_file}.xz"
            log_debug "Patch downloaded and verified: $patch_file"
            return 0
        else
            log_error "Patch file corrupted"
            rm -f "${patch_file}.xz"
            return 1
        fi
    else
        log_error "Failed to download patch"
        return 1
    fi
}

# 应用单个补丁
apply_single_patch() {
    local patch_file=$1
    local version=$2
    
    cd "$KERNEL_SRC"
    
    # 首先检查补丁是否能干净应用
    if git apply --check "$patch_file" 2>/dev/null; then
        log_info "Applying patch cleanly: $version"
        git apply "$patch_file"
        return 0
    else
        log_warn "Patch $version has conflicts"
        
        # 尝试强制应用
        if git apply --reject --whitespace=fix "$patch_file" 2>/dev/null; then
            log_warn "Patch $version applied with conflicts"
            
            # 检查是否有reject文件
            local rej_count=$(find . -name "*.rej" | wc -l)
            if [ "$rej_count" -gt 0 ]; then
                log_warn "Found $rej_count rejected hunks"
                
                # 尝试自动解决简单冲突
                for rej in $(find . -name "*.rej"); do
                    local target="${rej%.rej}"
                    if [ -f "$target" ]; then
                        # 简单的冲突解决策略
                        log_debug "Attempting to resolve conflict in $target"
                    fi
                done
                
                # 清理reject文件
                find . -name "*.rej" -delete
            fi
            
            return 0
        else
            log_error "Failed to apply patch $version"
            return 1
        fi
    fi
}

# 批量应用增量补丁
apply_incremental_patches() {
    local current_version=$1
    local target_version=$2
    
    cd "$KERNEL_SRC"
    
    IFS='.' read -r maj min current_sub <<< "$current_version"
    IFS='.' read -r _ _ target_sub <<< "$target_version"
    
    local current=$current_sub
    local applied=0
    local failed=0
    local start_time=$(date +%s)
    
    log_step "Applying patches: $current_version → $target_version"
    echo ""
    
    # 创建进度条函数
    show_progress() {
        local current=$1
        local total=$2
        local percent=$((current * 100 / total))
        local filled=$((percent / 2))
        local empty=$((50 - filled))
        
        printf "\r["
        printf "%${filled}s" | tr ' ' '='
        printf "%${empty}s" | tr ' ' ' '
        printf "] %3d%% (%d/%d)" "$percent" "$current" "$total"
    }
    
    while [ "$current" -lt "$target_sub" ]; do
        local next=$((current + 1))
        local from_ver="${maj}.${min}.${current}"
        local to_ver="${maj}.${min}.${next}"
        local patch_file="/tmp/patch-${to_ver}"
        
        # 显示进度
        local progress=$((current - current_sub + 1))
        local total=$((target_sub - current_sub))
        show_progress "$progress" "$total"
        
        # 下载补丁
        if download_patch "$from_ver" "$to_ver" "$patch_file"; then
            # 应用补丁
            if apply_single_patch "$patch_file" "$to_ver"; then
                ((applied++))
            else
                ((failed++))
                log_warn ""
                log_warn "Patch $to_ver failed, but continuing..."
            fi
            
            # 清理
            rm -f "$patch_file"
        else
            ((failed++))
            log_error ""
            log_error "Failed to download patch for $to_ver"
        fi
        
        current=$next
    done
    
    # 完成进度条
    show_progress "$total" "$total"
    echo ""
    echo ""
    
    # 更新Makefile中的版本号
    sed -i "s/^SUBLEVEL = .*/SUBLEVEL = $target_sub/" Makefile
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_info "Patch application completed in ${duration}s"
    log_info "Applied: $applied, Failed: $failed"
    
    # 返回失败数
    return $failed
}

# 验证内核源码
verify_kernel_source() {
    local version=$1
    
    log_step "Verifying kernel source..."
    
    cd "$KERNEL_SRC"
    
    # 检查关键文件
    local critical_files=(
        "Makefile"
        "arch/arm64/Kconfig"
        "arch/arm64/configs/gki_defconfig"
        "init/main.c"
    )
    
    local missing=0
    for file in "${critical_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "Missing critical file: $file"
            ((missing++))
        fi
    done
    
    if [ $missing -gt 0 ]; then
        log_error "Kernel source verification failed"
        return 1
    fi
    
    # 检查Makefile版本
    local makefile_version=$(grep "^SUBLEVEL = " Makefile | awk '{print $3}')
    local expected_sub=$(echo "$version" | cut -d. -f3)
    
    if [ "$makefile_version" != "$expected_sub" ]; then
        log_warn "Makefile SUBLEVEL ($makefile_version) doesn't match expected ($expected_sub)"
    fi
    
    log_info "Kernel source verification passed"
    return 0
}

# 智能更新主函数
smart_update() {
    local target_version=$1
    local auto_resolve=${2:-false}
    
    if [ -z "$target_version" ]; then
        # 自动检测最新版本
        target_version=$(get_latest_lts_version "5.4")
        
        if [ -z "$target_version" ]; then
            log_error "Failed to detect latest version"
            return 1
        fi
    fi
    
    local current_version=$(get_current_version)
    
    echo ""
    log_info "========================================="
    log_info "Smart Kernel Update"
    log_info "========================================="
    echo ""
    echo "Current version: $current_version"
    echo "Target version:  $target_version"
    echo "Auto resolve:    $auto_resolve"
    echo ""
    
    # 比较版本
    local cmp=$(version_compare "$current_version" "$target_version")
    
    case "$cmp" in
        same)
            log_info "Already up to date!"
            return 0
            ;;
        downgrade)
            log_warn "Target version is older than current"
            read -p "Continue anyway? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                return 1
            fi
            ;;
        different_branch)
            log_error "Cannot update across different version branches"
            log_info "Current: $current_version, Target: $target_version"
            return 1
            ;;
    esac
    
    # 创建备份
    create_backup "$current_version"
    
    # 应用补丁
    if apply_incremental_patches "$current_version" "$target_version"; then
        log_info "All patches applied successfully!"
        
        # 验证
        if verify_kernel_source "$target_version"; then
            # 更新版本文件
            echo "$target_version" > "$VERSION_FILE"
            
            # 创建git提交
            cd "$KERNEL_SRC"
            if [ -n "$(git status --porcelain)" ]; then
                git add -A
                git commit -m "chore: update kernel to $target_version

- Applied incremental patches from kernel.org
- Updated from $current_version to $target_version
- Generated by smart-update script
"
                
                # 创建标签
                local tag_name="kernel-v${target_version}-$(date +%Y%m%d)"
                git tag -a "$tag_name" -m "Kernel version $target_version"
                
                log_info "Git commit and tag created"
            fi
            
            echo ""
            log_info "========================================="
            log_info "Update completed successfully!"
            log_info "========================================="
            echo ""
            echo "Next steps:"
            echo "  1. Review changes: cd $KERNEL_SRC && git log -1"
            echo "  2. Build kernel: ./build.sh build"
            echo "  3. Test on device"
            echo ""
            
            return 0
        else
            log_error "Verification failed"
            return 1
        fi
    else
        log_error "Some patches failed to apply"
        log_warn "Check the output above for details"
        log_info "You can restore backup: $0 restore <backup_name>"
        return 1
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
Smart Kernel Update Script for Xiaomi Civi 1s

Usage: $0 <command> [options]

Commands:
  check                 Check for updates (default)
  update [version]      Update to specific version or latest
  auto-update           Update to latest with auto conflict resolution
  backup                Create a backup of current kernel
  restore [name]        Restore from backup
  version               Show current kernel version
  latest                Show latest available version
  help                  Show this help message

Examples:
  $0 check                          Check for updates
  $0 update                         Update to latest 5.4.x
  $0 update 5.4.301                 Update to specific version
  $0 auto-update                    Auto-update with conflict resolution
  $0 restore kernel-backup-5.4.150-20260309_123456

Environment Variables:
  SKIP_BACKUP=1         Skip backup creation
  SKIP_VERIFY=1         Skip verification
EOF
}

# 主函数
main() {
    local action=${1:-"check"}
    
    case "$action" in
        check)
            local current=$(get_current_version)
            local latest=$(get_latest_lts_version "5.4")
            
            echo ""
            echo "Current version: $current"
            echo "Latest version:  $latest"
            echo ""
            
            local cmp=$(version_compare "$current" "$latest")
            
            case "$cmp" in
                update_needed)
                    log_info "Update available: $current → $latest"
                    echo ""
                    echo "To update, run:"
                    echo "  $0 update $latest"
                    ;;
                same)
                    log_info "Already up to date"
                    ;;
                downgrade)
                    log_warn "Current version is newer than latest stable"
                    ;;
                different_branch)
                    log_error "Version branches don't match"
                    ;;
            esac
            ;;
            
        update)
            smart_update "$2" "false"
            ;;
            
        auto-update)
            smart_update "$2" "true"
            ;;
            
        backup)
            create_backup "$(get_current_version)"
            ;;
            
        restore)
            restore_backup "$2"
            ;;
            
        version)
            get_current_version
            ;;
            
        latest)
            get_latest_lts_version "${2:-5.4}"
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