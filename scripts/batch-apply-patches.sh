#!/bin/bash
# 批量应用补丁并记录结果

KERNEL_SRC="/home/cola/civi1s-sukisu-build/Xiaomi_Kernel_OpenSource-zijin-s-oss"
VERSION_FILE="/home/cola/civi1s-sukisu-build/KERNEL_VERSION"
LOG_FILE="/home/cola/civi1s-sukisu-build/docs/PATCH_APPLICATION_LOG.md"

apply_patch_batch() {
    local from=$1
    local to=$2

    cd "$KERNEL_SRC"

    echo "## Patch Application Log: 5.4.$from → 5.4.$to" >> "$LOG_FILE"
    echo "Started: $(date)" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    local current=$from
    local applied=0
    local skipped=0
    local failed=0

    while [ "$current" -lt "$to" ]; do
        local next=$((current + 1))
        local patch_url="https://cdn.kernel.org/pub/linux/kernel/v5.x/incr/patch-5.4.$current-$next.xz"
        local patch_file="/tmp/patch-5.4.$next"

        echo "### Applying 5.4.$current → 5.4.$next" >> "$LOG_FILE"

        if curl -L --silent --max-time 30 "$patch_url" -o "${patch_file}.xz" 2>/dev/null; then
            xz -d -f "${patch_file}.xz" 2>/dev/null

            if git apply --check "$patch_file" 2>/dev/null; then
                git apply "$patch_file" 2>/dev/null
                sed -i "s/^SUBLEVEL = .*/SUBLEVEL = $next/" Makefile
                echo "- Status: ✅ Applied" >> "$LOG_FILE"
                ((applied++))
            else
                echo "- Status: ⚠️ Skipped (conflict)" >> "$LOG_FILE"
                ((skipped++))
            fi

            rm -f "$patch_file"
        else
            echo "- Status: ❌ Failed to download" >> "$LOG_FILE"
            ((failed++))
        fi

        echo "" >> "$LOG_FILE"
        current=$next
    done

    echo "" >> "$LOG_FILE"
    echo "**Summary:**" >> "$LOG_FILE"
    echo "- Applied: $applied" >> "$LOG_FILE"
    echo "- Skipped: $skipped" >> "$LOG_FILE"
    echo "- Failed: $failed" >> "$LOG_FILE"
    echo "Completed: $(date)" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    echo "$to" > "$VERSION_FILE"

    echo "Applied: $applied, Skipped: $skipped, Failed: $failed"
}

apply_patch_batch $1 $2