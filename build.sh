#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
KERNEL_SRC="$PROJECT_ROOT/Xiaomi_Kernel_OpenSource-zijin-s-oss"
TOOLCHAINS="$PROJECT_ROOT/toolchains"
OUT_DIR="$KERNEL_SRC/out"
ANYKERNEL="$PROJECT_ROOT/AnyKernel3"

TOOLCHAIN_URL="https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b"
KERNEL_REPO="https://github.com/MiCode/Xiaomi_Kernel_OpenSource"
KERNEL_BRANCH="zijin-s-oss"
KSU_VERSION="susfs-v1.5.5"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_dependencies() {
    log_info "Checking build dependencies..."
    local deps="bc bison build-essential ccache curl flex g++-multilib gcc-multilib git gnupg gperf liblz4-tool libncurses-dev libssl-dev libxml2-utils lzop rsync squashfs-tools xsltproc zip zlib1g-dev python3 python-is-python3 gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu"
    
    if ! dpkg -l $deps > /dev/null 2>&1; then
        log_warn "Missing dependencies. Installing..."
        sudo apt-get update
        sudo apt install -y $deps
    fi
    log_info "Dependencies OK"
}

download_toolchain() {
    if [ ! -d "$TOOLCHAINS/clang" ]; then
        log_info "Downloading Clang toolchain..."
        mkdir -p "$TOOLCHAINS"
        git clone --depth=1 "$TOOLCHAIN_URL" "$TOOLCHAINS/clang"
    else
        log_info "Toolchain already exists"
    fi
}

download_kernel() {
    local version="$1"
    if [ -n "$version" ]; then
        log_info "Downloading kernel version $version..."
        rm -rf "$KERNEL_SRC"
        git clone --depth=1 -b "$version" "$KERNEL_REPO" "$KERNEL_SRC" 2>/dev/null || {
            log_warn "Version $version not found, using default branch"
            git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_SRC"
        }
    elif [ ! -d "$KERNEL_SRC" ]; then
        log_info "Downloading kernel source..."
        git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_SRC"
    else
        log_info "Kernel source already exists"
    fi
}

integrate_kernelsu() {
    log_info "Integrating KernelSU..."
    cd "$KERNEL_SRC"
    curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s "$KSU_VERSION" || {
        log_warn "KernelSU setup returned non-zero, continuing..."
    }
    cd "$PROJECT_ROOT"
}

apply_patches() {
    log_info "Applying compatibility patches..."
    cd "$KERNEL_SRC"
    bash "$PROJECT_ROOT/patches/apply-kernelsu-compat.sh"
    cd "$PROJECT_ROOT"
}

apply_config() {
    log_info "Applying kernel config..."
    local defconfig="$KERNEL_SRC/arch/arm64/configs/gki_defconfig"
    
    grep -q "CONFIG_KSU=y" "$defconfig" || cat >> "$defconfig" << EOF
CONFIG_KSU=y
CONFIG_KPROBE_EVENTS=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_HAS_KSU_VERSION_H=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
EOF
}

build_kernel() {
    log_info "Building kernel..."
    cd "$KERNEL_SRC"
    
    export PATH="$TOOLCHAINS/clang/bin:$PATH"
    export KBUILD_BUILD_HOST="Local-Build"
    export KBUILD_BUILD_USER="Builder"
    
    make -j"$(nproc --all)" \
        O=out \
        ARCH=arm64 \
        CC=clang \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-gnu- \
        gki_defconfig
    
    make -j"$(nproc --all)" \
        O=out \
        ARCH=arm64 \
        CC=clang \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-gnu-
    
    cd "$PROJECT_ROOT"
}

package_kernel() {
    log_info "Packaging kernel..."
    
    if [ ! -d "$ANYKERNEL" ]; then
        git clone https://github.com/osm0sis/AnyKernel3 "$ANYKERNEL"
        rm -rf "$ANYKERNEL/.git*"
    fi
    
    cp "$KERNEL_SRC/out/arch/arm64/boot/Image" "$ANYKERNEL/"
    
    sed -i 's/do.devicecheck=1/do.devicecheck=0/g' "$ANYKERNEL/anykernel.sh"
    sed -i 's!block=/dev/block/platform/omap/omap_hsmmc.0/by-name/boot;!block=auto;!g' "$ANYKERNEL/anykernel.sh"
    sed -i 's/is_slot_device=0;/is_slot_device=auto;/g' "$ANYKERNEL/anykernel.sh"
    sed -i 's/device.name1=.*/device.name1=civi1s/g' "$ANYKERNEL/anykernel.sh"
    sed -i 's/device.name2=.*/device.name2=civi_1s/g' "$ANYKERNEL/anykernel.sh"
    sed -i 's/device.name3=.*/device.name3=civi/g' "$ANYKERNEL/anykernel.sh"
    
    local output_name="SukiSU-Kernel-Civi1s-$(date +%Y%m%d).zip"
    cd "$ANYKERNEL"
    zip -r "$PROJECT_ROOT/$output_name" .
    cd "$PROJECT_ROOT"
    
    log_info "Kernel package created: $output_name"
    echo "$output_name"
}

update_kernel() {
    local target_version="$1"
    
    if [ -z "$target_version" ]; then
        log_error "Please specify kernel version (e.g., 5.4.280)"
        exit 1
    fi
    
    log_info "Updating kernel to $target_version..."
    
    local current_version=$(grep "^VERSION = " "$KERNEL_SRC/Makefile" | awk '{print $3}').$(grep "^PATCHLEVEL = " "$KERNEL_SRC/Makefile" | awk '{print $3}').$(grep "^SUBLEVEL = " "$KERNEL_SRC/Makefile" | awk '{print $3}')
    
    log_info "Current version: $current_version"
    
    IFS='.' read -r MAJOR MINOR CURRENT_SUB <<< "$current_version"
    IFS='.' read -r _ _ TARGET_SUB <<< "$target_version"
    
    if [ "$TARGET_SUB" -le "$CURRENT_SUB" ]; then
        log_error "Target version must be newer than current version"
        exit 1
    fi
    
    cd "$KERNEL_SRC"
    
    local current="$CURRENT_SUB"
    while [ "$current" -lt "$TARGET_SUB" ]; do
        local next=$((current + 1))
        local patch_url="https://cdn.kernel.org/pub/linux/kernel/v5.x/incr/patch-5.4.$current-$next.xz"
        
        log_info "Applying patch 5.4.$current → 5.4.$next"
        
        if curl -L "$patch_url" -o /tmp/patch.xz 2>/dev/null; then
            xz -d -f /tmp/patch.xz
            if git apply /tmp/patch; then
                log_info "Patch 5.4.$next applied successfully"
            else
                log_warn "Patch 5.4.$next failed, may need manual resolution"
                log_warn "Check /tmp/patch for details"
            fi
        else
            log_error "Failed to download patch for 5.4.$next"
            exit 1
        fi
        
        current=$next
    done
    
    sed -i "s/SUBLEVEL = .*/SUBLEVEL = $TARGET_SUB/" Makefile
    
    cd "$PROJECT_ROOT"
    log_info "Kernel updated to 5.4.$TARGET_SUB"
}

show_help() {
    echo "SukiSU Kernel Builder for Xiaomi Civi 1s"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  build           Build kernel with current source"
    echo "  clean           Clean build output"
    echo "  update <ver>    Update kernel to specific 5.4.x version (e.g., 5.4.280)"
    echo "  full            Full build: download, patch, build, package"
    echo "  help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 build                    Build with existing source"
    echo "  $0 update 5.4.200           Update to kernel 5.4.200"
    echo "  $0 full                     Complete build from scratch"
}

clean_build() {
    log_info "Cleaning build output..."
    rm -rf "$KERNEL_SRC/out"
    log_info "Clean complete"
}

full_build() {
    log_info "Starting full build..."
    check_dependencies
    download_toolchain
    download_kernel
    integrate_kernelsu
    apply_patches
    apply_config
    build_kernel
    package_kernel
    log_info "Full build complete!"
}

case "$1" in
    build)
        build_kernel
        package_kernel
        ;;
    clean)
        clean_build
        ;;
    update)
        update_kernel "$2"
        integrate_kernelsu
        apply_patches
        apply_config
        build_kernel
        package_kernel
        ;;
    full)
        full_build
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac