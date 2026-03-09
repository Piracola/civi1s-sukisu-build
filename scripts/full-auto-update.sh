#!/bin/bash
# 完整的自动化内核更新脚本
# 批量应用补丁并自动跳过冲突

set -e

KERNEL_SRC="/home/cola/civi1s-sukisu-build/Xiaomi_Kernel_OpenSource-zijin-s-oss"
VERSION_FILE="/home/cola/civi1s-sukisu-build/KERNEL_VERSION"
LOG_FILE="/home/cola/civi1s-sukisu-build/docs/FULL_UPDATE_LOG.md"

get_current_version() {
    cd "$KERNEL_SRC"
    grep "^SUBLEVEL = " Makefile | awk '{print $3}'
}

batch_update() {
    local target_version=${1:-302}
    local batch_size=${2:-20}

    local current=$(get_current_version)

    echo "# Full Kernel Update Log" > "$LOG_FILE"
    echo "Started: $(date)" >> "$LOG_FILE"
    echo "Target: 5.4.$target_version" >> "$LOG_FILE"
    echo "Batch size: $batch_size" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    local total_applied=0
    local total_skipped=0
    local total_failed=0
    local batch_num=0

    while [ "$current" -lt "$target_version" ]; do
        ((batch_num++))
        local batch_end=$((current + batch_size))
        [ "$batch_end" -gt "$target_version" ] && batch_end=$target_version

        echo "" >> "$LOG_FILE"
        echo "## Batch $batch_num: 5.4.$current → 5.4.$batch_end" >> "$LOG_FILE"
        echo "Started: $(date)" >> "$LOG_FILE"

        local batch_applied=0
        local batch_skipped=0
        local batch_failed=0
        local batch_current=$current

        while [ "$batch_current" -lt "$batch_end" ]; do
            local next=$((batch_current + 1))
            local patch_url="https://cdn.kernel.org/pub/linux/kernel/v5.x/incr/patch-5.4.$batch_current-$next.xz"
            local patch_file="/tmp/patch-5.4.$next"

            echo -n "Applying 5.4.$batch_current → 5.4.$next: "

            if curl -L --silent --max-time 30 "$patch_url" -o "${patch_file}.xz" 2>/dev/null; then
                xz -d -f "${patch_file}.xz" 2>/dev/null

                if git apply --check "$patch_file" 2>/dev/null; then
                    git apply "$patch_file" 2>/dev/null
                    sed -i "s/^SUBLEVEL = .*/SUBLEVEL = $next/" Makefile
                    echo "✅"
                    echo "- 5.4.$next: ✅ Applied" >> "$LOG_FILE"
                    ((batch_applied++))
                else
                    echo "⚠️ Skipped"
                    echo "- 5.4.$next: ⚠️ Skipped (conflict)" >> "$LOG_FILE"
                    ((batch_skipped++))
                fi

                rm -f "$patch_file"
            else
                echo "❌ Failed"
                echo "- 5.4.$next: ❌ Failed to download" >> "$LOG_FILE"
                ((batch_failed++))
            fi

            batch_current=$next
        done

        echo "" >> "$LOG_FILE"
        echo "Batch $batch_num Summary:" >> "$LOG_FILE"
        echo "- Applied: $batch_applied" >> "$LOG_FILE"
        echo "- Skipped: $batch_skipped" >> "$LOG_FILE"
        echo "- Failed: $batch_failed" >> "$LOG_FILE"
        echo "Completed: $(date)" >> "$LOG_FILE"

        total_applied=$((total_applied + batch_applied))
        total_skipped=$((total_skipped + batch_skipped))
        total_failed=$((total_failed + batch_failed))

        current=$(get_current_version)

        # 每批次后测试编译配置
        echo "Testing build configuration..."
        if make -j8 O=out ARCH=arm64 gki_defconfig >/dev/null 2>&1; then
            echo "✅ Configuration OK"
            echo "Build config: ✅ OK" >> "$LOG_FILE"
        else
            echo "⚠️ Configuration failed"
            echo "Build config: ❌ Failed" >> "$LOG_FILE"
        fi

        echo ""
    done

    echo "" >> "$LOG_FILE"
    echo "# Final Summary" >> "$LOG_FILE"
    echo "Total Applied: $total_applied" >> "$LOG_FILE"
    echo "Total Skipped: $total_skipped" >> "$LOG_FILE"
    echo "Total Failed: $total_failed" >> "$LOG_FILE"
    echo "Final Version: 5.4.$(get_current_version)" >> "$LOG_FILE"
    echo "Completed: $(date)" >> "$LOG_FILE"

    echo "$current" > "$VERSION_FILE"

    echo ""
    echo "=== Update Complete ==="
    echo "Applied: $total_applied"
    echo "Skipped: $total_skipped"
    echo "Failed: $total_failed"
    echo "Final Version: 5.4.$(get_current_version)"
}

batch_update $1 $2