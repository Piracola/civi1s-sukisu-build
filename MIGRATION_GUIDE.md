# 小米 Civi 1S 内核更新项目迁移与开发指南

## 1. 项目概况
本项目的目标是将小米 Civi 1S (zijin) 的内核从官方开源码 (5.4.152) 更新至 Linux 5.4 LTS 的最新稳定版 (5.4.302)。

## 2. 当前进度与状态
- **内核版本**: 已尝试更新至 **5.4.302**。
- **构建状态**: ❌ **编译失败**。
- **主要工作**:
    - 实现了自动化更新系统 (`update-kernel.sh`) 和版本管理系统 (`version-manager.sh`)。
    - 升级了 GitHub Actions 构建环境至 Ubuntu 22.04，解决了排队问题。
    - 尝试了一次性更新至 5.4.302，但遇到了极高的冲突率（约 98%）。
    - 手动修复了 `arch/arm64/kernel/process.c`, `include/net/udp.h`, `net/packet/af_packet.c`, `mm/oom_kill.c`, `drivers/char/random.c` 中的部分编译错误。

## 3. 踩过的坑与技术挑战 (Critical Pitfalls)

### 3.1 极高的补丁冲突率
小米的内核源码在 5.4.152 基准上进行了大量的厂商定制 (Qualcomm & Xiaomi)。直接应用 upstream 补丁时，API 和函数签名的差异导致 98% 的补丁无法自动合并。

### 3.2 编译错误连环爆炸
由于大量补丁被跳过，导致内核代码处于一个不一致的状态：
- **API 不匹配**: upstream 补丁更新了底层 API，但调用处的小米代码仍保留旧版本。
- **结构体定义缺失**: 例如 `binder_proc` 结构体中缺少 `cred` 成员。
- **变量未定义**: 例如 `rc`, `sbi` 等在重构后的代码中丢失声明。

### 3.3 构建环境限制
初步尝试使用老旧的 Ubuntu 20.04 运行 GitHub Actions 会导致无限排队。目前已通过升级 runner 解决。

## 4. 后续开发建议

> [!IMPORTANT]
> **强烈建议：回滚并重新开始增量更新。**
> 当前 5.4.302 的代码状态过于混乱，手动修复所有错误的工作量巨大且容易引入难以察觉的运行时 Bug。

**推荐的修复路径：**
1. **回滚**: 将内核源码恢复到原始的 5.4.152 分支。
2. **增量更新**: 每次仅应用 5-10 个小版本的补丁（例如 5.4.152 -> 5.4.160）。
3. **即时解决**: 每一步更新后立即编译测试。如果遇到冲突，分析是保留厂商代码还是合并 upstream 修复。
4. **编译优化**: 优先解决 `fs/ext4`, `fs/f2fs`, `drivers/android/binder.c`, `security/selinux` 中的核心 API 冲突。

## 5. 项目文件说明
- `update-kernel.sh`: 自动下载并应用 kernel.org 补丁。
- `version-manager.sh`: 管理 Git 标签和版本信息。
- `build.sh`: 本地编译脚本。
- `docs/`: 详细的冲突分析 report、修复计划和日志。
- `Xiaomi_Kernel_OpenSource-zijin-s-oss/`: 内核源码主目录。

## 6. 环境迁移指南
1. **源码包**: 解压 `project_backup.tar.gz`。
2. **工具链**: 项目需要 AOSP Clang 12.0+ 或 GCC 依赖。
3. **恢复**: 执行 `cd Xiaomi_Kernel_OpenSource-zijin-s-oss && git status` 确认当前工作区状态。
4. **继续**: 参考 `docs/COMPILE_ERROR_FIX_PLAN.md` 继续之前的修复工作。

---
**开发者记录**: 2026-03-09
**状态**: 源码已提交并推送，准备打包迁移。
