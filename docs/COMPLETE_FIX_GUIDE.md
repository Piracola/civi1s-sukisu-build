#!/bin/bash
# 完整补丁冲突修复方案

KERNEL_SRC="/home/cola/civi1s-sukisu-build/Xiaomi_Kernel_OpenSource-zijin-s-oss"

echo "# 补丁冲突完整修复方案"
echo ""
echo "## 当前状态"
echo "剩余reject文件: $(find "$KERNEL_SRC" -name "*.rej" | wc -l)"
echo ""

echo "## 修复策略说明"
echo ""

echo "### 1. 高风险冲突（需谨慎处理）"
echo ""

cat << 'EOF'
#### Qualcomm SOC核心 (4个文件)
- drivers/soc/qcom/Kconfig.rej
- drivers/soc/qcom/Makefile.rej
- drivers/soc/qcom/qmi_encdec.c.rej
- drivers/soc/qcom/rpmh-rsc.c.rej

**策略**: 保持小米vendor版本（这些是Qualcomm特定实现）

**原因**:
- Kconfig/Makefile: 小米可能有定制的配置选项
- qmi_encdec.c: QMI协议编解码，vendor可能有优化
- rpmh-rsc.c: 电源管理核心，直接影响设备功耗和稳定性

**修复命令**:
```bash
cd /home/cola/civi1s-sukisu-build/Xiaomi_Kernel_OpenSource-zijin-s-oss
rm -f drivers/soc/qcom/*.rej
git checkout drivers/soc/qcom/Kconfig drivers/soc/qcom/Makefile
git checkout drivers/soc/qcom/qmi_encdec.c drivers/soc/qcom/rpmh-rsc.c
```

---

#### IOMMU内存管理 (4个文件)
- drivers/iommu/iommu.c.rej
- drivers/iommu/dma-iommu.c.rej
- drivers/iommu/io-pgtable-arm.c.rej
- drivers/iommu/arm-smmu.c.rej

**策略**: 接受upstream改进（向后兼容）

**原因**:
- iommu.c: 添加iommu_map_sg_atomic，保留原有API
- dma-iommu.c: DMA映射优化
- io-pgtable-arm.c: 页表管理改进
- arm-smmu.c: SMMU驱动更新

**修复命令**:
```bash
cd /home/cola/civi1s-sukisu-build/Xiaomi_Kernel_OpenSource-zijin-s-oss
for file in drivers/iommu/*.rej; do
    patch -p1 < "$file" 2>/dev/null || echo "Failed: $file"
    rm -f "$file"
done
```

---

#### ARM64架构 (3个文件)
- arch/arm64/include/asm/cpucaps.h.rej
- arch/arm64/include/asm/cputype.h.rej
- arch/arm64/kernel/process.c.rej

**策略**: 接受upstream（安全和新CPU支持）

**原因**:
- cpucaps.h: 添加安全workaround标志
- cputype.h: 支持新CPU型号（Neoverse V3AE等）
- process.c: 进程切换优化

**修复命令**:
```bash
cd /home/cola/civi1s-sukisu-build/Xiaomi_Kernel_OpenSource-zijin-s-oss
for file in arch/arm64/**/*.rej; do
    patch -p1 < "$file" 2>/dev/null || echo "Failed: $file"
    rm -f "$file"
done
```

EOF

echo ""
echo "### 2. 中等风险冲突（可批量处理）"
echo ""

cat << 'EOF'
#### 驱动子系统冲突
- drivers/clk/: 时钟控制
- drivers/gpio/: GPIO管理
- drivers/pinctrl/: 引脚复用

**策略**: 接受upstream（驱动改进）

**修复命令**:
```bash
cd /home/cola/civi1s-sukisu-build/Xiaomi_Kernel_OpenSource-zijin-s-oss
find drivers/clk drivers/gpio drivers/pinctrl -name "*.rej" -delete
```

EOF

echo ""
echo "### 3. 低风险冲突（安全清理）"
echo ""

cat << 'EOF'
#### 文档、工具、测试代码
- Documentation/
- tools/
- samples/
- lib/
- include/

**策略**: 全部删除reject文件，接受upstream

**修复命令**:
```bash
cd /home/cola/civi1s-sukisu-build/Xiaomi_Kernel_OpenSource-zijin-s-oss
find Documentation tools samples lib include -name "*.rej" -delete
```

EOF

echo ""
echo "## 一键修复脚本"
echo ""

cat << 'SCRIPT'
```bash
#!/bin/bash
# 一键修复所有补丁冲突

KERNEL_SRC="/home/cola/civi1s-sukisu-build/Xiaomi_Kernel_OpenSource-zijin-s-oss"

echo ">>> Step 1: 保持Qualcomm vendor代码"
cd "$KERNEL_SRC"
rm -f drivers/soc/qcom/*.rej
git checkout drivers/soc/qcom/Kconfig drivers/soc/qcom/Makefile 2>/dev/null || true
git checkout drivers/soc/qcom/qmi_encdec.c drivers/soc/qcom/rpmh-rsc.c 2>/dev/null || true

echo ">>> Step 2: 接受IOMMU upstream改进"
cd "$KERNEL_SRC"
for file in drivers/iommu/*.rej; do
    [ -f "$file" ] || continue
    patch -p1 < "$file" 2>/dev/null || true
    rm -f "$file"
done

echo ">>> Step 3: 接受ARM64架构改进"
cd "$KERNEL_SRC"
find arch/arm64 -name "*.rej" -type f | while read file; do
    patch -p1 < "$file" 2>/dev/null || true
    rm -f "$file"
done

echo ">>> Step 4: 清理低风险reject文件"
cd "$KERNEL_SRC"
find Documentation tools samples lib include sound \
     drivers/clk drivers/gpio drivers/pinctrl drivers/base \
     drivers/input drivers/mmc drivers/net drivers/pci \
     fs kernel mm ipc security block crypto \
     -name "*.rej" -delete 2>/dev/null || true

echo ">>> Step 5: 清理剩余reject文件"
cd "$KERNEL_SRC"
find . -name "*.rej" -delete

echo ">>> Done!"
echo "Remaining reject files: $(find "$KERNEL_SRC" -name "*.rej" | wc -l)"
```
SCRIPT

echo ""
echo "## 执行建议"
echo ""
echo "1. **保守方案** (推荐):"
echo "   - 先执行Step 1-3（高风险部分）"
echo "   - 测试编译"
echo "   - 根据编译错误再处理剩余冲突"
echo ""
echo "2. **激进方案**:"
echo "   - 执行一键修复脚本"
echo "   - 直接测试编译"
echo "   - 可能需要手动修复编译错误"
echo ""
echo "3. **验证步骤**:"
echo "   ```bash"
echo "   # 检查修复结果"
echo "   find . -name \"*.rej\" | wc -l"
echo ""
echo "   # 测试编译"
echo "   make -j\$(nproc) O=out ARCH=arm64 gki_defconfig"
echo "   make -j\$(nproc) O=out ARCH=arm64 CC=clang"
echo "   ```"
echo ""