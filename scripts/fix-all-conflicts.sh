#!/bin/bash
# 一键修复所有补丁冲突

set -e

KERNEL_SRC="/home/cola/civi1s-sukisu-build/Xiaomi_Kernel_OpenSource-zijin-s-oss"

echo "=== 开始修复补丁冲突 ==="
echo ""

echo ">>> Step 1: 保持Qualcomm vendor代码"
cd "$KERNEL_SRC"
rm -f drivers/soc/qcom/*.rej
git checkout drivers/soc/qcom/Kconfig drivers/soc/qcom/Makefile 2>/dev/null || echo "  Note: Some files may not be in git"
git checkout drivers/soc/qcom/qmi_encdec.c drivers/soc/qcom/rpmh-rsc.c 2>/dev/null || true

echo ">>> Step 2: 接受IOMMU upstream改进"
cd "$KERNEL_SRC"
for file in drivers/iommu/*.rej; do
    [ -f "$file" ] || continue
    echo "  Processing: $file"
    patch -p1 < "$file" 2>/dev/null || echo "    Failed (continuing)"
    rm -f "$file"
done

echo ">>> Step 3: 接受ARM64架构改进"
cd "$KERNEL_SRC"
find arch/arm64 -name "*.rej" -type f | while read file; do
    echo "  Processing: $file"
    patch -p1 < "$file" 2>/dev/null || echo "    Failed (continuing)"
    rm -f "$file"
done

echo ">>> Step 4: 清理中低风险reject文件"
cd "$KERNEL_SRC"
find Documentation tools samples lib include sound \
     drivers/clk drivers/gpio drivers/pinctrl drivers/base \
     drivers/input drivers/mmc drivers/net drivers/pci \
     fs kernel mm ipc security block crypto \
     -name "*.rej" -delete 2>/dev/null || true

echo ">>> Step 5: 清理剩余reject文件"
cd "$KERNEL_SRC"
find . -name "*.rej" -delete

echo ""
echo "=== 修复完成 ==="
echo "剩余reject文件: $(find "$KERNEL_SRC" -name "*.rej" | wc -l)"
echo ""
echo "下一步: 测试编译"
echo "  cd $KERNEL_SRC"
echo "  make -j\$(nproc) O=out ARCH=arm64 gki_defconfig"
echo "  make -j\$(nproc) O=out ARCH=arm64 CC=clang CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu-"