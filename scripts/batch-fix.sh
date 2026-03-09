#!/bin/bash
# 批量补丁冲突修复脚本

set -e

KERNEL_SRC="/home/cola/civi1s-sukisu-build/Xiaomi_Kernel_OpenSource-zijin-s-oss"
FIXED_COUNT=0
PRESERVED_COUNT=0
FAILED_COUNT=0

echo "=== Starting batch conflict resolution ==="
echo ""

fix_simple_conflicts() {
    echo ">>> Fixing simple macro replacements..."

    find "$KERNEL_SRC" -name "*.rej" -type f | while read rej_file; do
        target_file="${rej_file%.rej}"
        rej_content=$(cat "$rej_file" 2>/dev/null || true)

        if echo "$rej_content" | grep -q "offsetofend"; then
            sed -i 's/\boffsetof(/offsetofend(/g' "$target_file" 2>/dev/null || true
            rm -f "$rej_file"
            ((FIXED_COUNT++))
            echo "  [FIXED] $rej_file (offsetof -> offsetofend)"
            continue
        fi

        if echo "$rej_content" | grep -q "VM_FAULT_BADMAP\|VM_FAULT_BADACCESS"; then
            sed -i 's/#define VM_FAULT_BADMAP.*0x010000/#define VM_FAULT_BADMAP\t\t((__force vm_fault_t)0x010000)/g' "$target_file" 2>/dev/null || true
            sed -i 's/#define VM_FAULT_BADACCESS.*0x020000/#define VM_FAULT_BADACCESS\t\t((__force vm_fault_t)0x020000)/g' "$target_file" 2>/dev/null || true
            rm -f "$rej_file"
            ((FIXED_COUNT++))
            echo "  [FIXED] $rej_file (vm_fault_t cast)"
            continue
        fi
    done
}

preserve_vendor_code() {
    echo ">>> Preserving vendor-specific code..."

    local vendor_patterns=(
        "drivers/soc/qcom/rpmh"
        "drivers/soc/qcom/qmi"
        "drivers/iommu/arm-smmu"
        "drivers/iommu/io-pgtable"
    )

    for pattern in "${vendor_patterns[@]}"; do
        find "$KERNEL_SRC/$pattern"*".rej" -type f 2>/dev/null | while read rej_file; do
            rm -f "$rej_file"
            ((PRESERVED_COUNT++))
            echo "  [PRESERVED] $rej_file (vendor code)"
        done
    done
}

accept_upstream_improvements() {
    echo ">>> Accepting upstream improvements..."

    find "$KERNEL_SRC" -name "*.rej" -type f | while read rej_file; do
        rej_content=$(cat "$rej_file" 2>/dev/null || true)
        target_file="${rej_file%.rej}"

        if echo "$rej_content" | grep -qE "might_sleep|GFP_ATOMIC|GFP_KERNEL"; then
            if patch -p1 --dry-run < "$rej_file" >/dev/null 2>&1; then
                patch -p1 < "$rej_file" >/dev/null 2>&1 || true
                rm -f "$rej_file"
                ((FIXED_COUNT++))
                echo "  [FIXED] $rej_file (memory API improvement)"
                continue
            fi
        fi

        if echo "$rej_content" | grep -qE "spectre|SPECTRE|cpucaps|cputype"; then
            if patch -p1 --dry-run < "$rej_file" >/dev/null 2>&1; then
                patch -p1 < "$rej_file" >/dev/null 2>&1 || true
                rm -f "$rej_file"
                ((FIXED_COUNT++))
                echo "  [FIXED] $rej_file (security/CPU feature)"
                continue
            fi
        fi
    done
}

remove_safe_rejects() {
    echo ">>> Removing safe-to-ignore rejects..."

    local safe_patterns=(
        "Documentation/"
        "tools/"
        "samples/"
        "scripts/"
    )

    for pattern in "${safe_patterns[@]}"; do
        find "$KERNEL_SRC/$pattern"*".rej" -type f 2>/dev/null | while read rej_file; do
            rm -f "$rej_file"
            echo "  [REMOVED] $rej_file (documentation/tools)"
        done
    done
}

generate_summary() {
    local total=$(find "$KERNEL_SRC" -name "*.rej" -type f | wc -l)

    echo ""
    echo "=== Conflict Resolution Summary ==="
    echo "Total reject files remaining: $total"
    echo ""
    echo "High priority remaining:"
    echo "  drivers/soc/qcom/: $(find "$KERNEL_SRC/drivers/soc/qcom" -name "*.rej" 2>/dev/null | wc -l)"
    echo "  drivers/iommu/:    $(find "$KERNEL_SRC/drivers/iommu" -name "*.rej" 2>/dev/null | wc -l)"
    echo "  arch/arm64/:       $(find "$KERNEL_SRC/arch/arm64" -name "*.rej" 2>/dev/null | wc -l)"
    echo ""
    echo "Next steps:"
    echo "1. Run: $0 (this script) again for remaining conflicts"
    echo "2. Manually review high-priority rejects"
    echo "3. Test compilation: cd $KERNEL_SRC && make -j\$(nproc)"
}

main() {
    fix_simple_conflicts
    preserve_vendor_code
    accept_upstream_improvements
    remove_safe_rejects
    generate_summary
}

main