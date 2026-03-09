# 内核自动化构建指南

## 概述

本项目旨在基于小米开源内核源代码，实现内核版本的自动化更新和构建。通过智能脚本和GitHub Actions，实现了从内核版本检测、更新、编译到发布的完整自动化流程。

### 当前状态

- **内核版本**: 5.4.302 LTS
- **基础版本**: 5.4.150 (小米官方)
- **KernelSU版本**: susfs-v1.5.5
- **最后更新**: 2026-03-09
- **更新补丁数**: 152个增量补丁

### 项目目标

1. 保持内核版本更新到最新LTS版本
2. 自动化构建和发布流程
3. 集成KernelSU和SUSFS功能
4. 确保设备兼容性和稳定性

---

## 自动化构建方案架构

### 2.1 智能更新系统

#### scripts/smart-update.sh

智能内核版本更新脚本，核心功能：

**自动检测**
- 从kernel.org获取最新LTS版本
- 比较当前版本与目标版本
- 生成更新计划

**增量更新**
- 下载官方增量补丁（patch-5.4.X-Y.xz）
- 逐个应用补丁
- 进度显示和错误处理

**冲突处理**
- 自动检测补丁冲突
- 尝试强制应用（--reject --whitespace=fix）
- 清理reject文件
- 继续后续补丁应用

**备份与恢复**
- 更新前自动备份关键文件
- 支持版本回滚
- 备份列表管理

**版本验证**
- 检查关键文件完整性
- 验证Makefile版本号
- Git提交和标签创建

### 2.2 GitHub Actions自动化

#### .github/workflows/smart-build.yml

完整的CI/CD工作流：

**触发条件**
- 定时触发：每周一凌晨2点（UTC）
- 手动触发：支持指定目标版本
- Push触发：main分支更新

**构建流程**
1. **检查更新** (check-updates job)
   - 获取当前版本
   - 检测最新LTS版本
   - 决定是否需要构建
   - 创建更新通知Issue

2. **构建内核** (build job)
   - 释放磁盘空间
   - 安装构建依赖
   - 缓存工具链
   - 执行智能更新
   - 集成KernelSU
   - 应用兼容性补丁
   - 编译内核
   - 打包发布

**优化特性**
- 工具链缓存：减少下载时间
- Swap扩展：提升编译稳定性
- 并行编译：充分利用CPU资源
- 增量构建：利用ccache加速

**发布流程**
- 创建GitHub Release
- 上传构建产物
- 更新KERNEL_VERSION文件
- 创建Git标签

### 2.3 本地构建脚本

#### build.sh

主构建脚本，支持多种构建模式：

**命令列表**
```bash
./build.sh full      # 完整构建（从零开始）
./build.sh build     # 仅编译（已有源码）
./build.sh update    # 更新内核版本
./build.sh clean     # 清理构建输出
./build.sh help      # 显示帮助信息
```

**构建流程**
1. 检查并安装依赖
2. 下载Clang工具链
3. 克隆内核源码
4. 集成KernelSU
5. 应用兼容性补丁
6. 配置内核选项
7. 编译内核
8. 打包AnyKernel3

---

## 使用指南

### 3.1 检查更新

检查当前内核版本和最新可用版本：

```bash
./scripts/smart-update.sh check
```

输出示例：
```
Current version: 5.4.302
Latest version:  5.4.302

[INFO] Already up to date
```

### 3.2 执行更新

#### 更新到最新LTS版本

```bash
./scripts/smart-update.sh update
```

#### 更新到指定版本

```bash
./scripts/smart-update.sh update 5.4.302
```

#### 带冲突自动解决的更新

```bash
./scripts/smart-update.sh auto-update
```

**更新过程**
1. 创建备份（.kernel_backups/）
2. 下载增量补丁
3. 逐个应用补丁（显示进度条）
4. 更新Makefile版本号
5. 创建Git提交和标签
6. 验证更新结果

### 3.3 本地构建

#### 完整构建

从零开始完整构建流程：

```bash
./build.sh full
```

包括：下载源码、集成KernelSU、编译、打包。

#### 仅编译

已有源码，仅执行编译：

```bash
./build.sh build
```

#### 清理构建

```bash
./build.sh clean
```

清理构建产物（out/目录）。

### 3.4 GitHub Actions使用

#### 自动触发

- **定时检查**: 每周一凌晨2点（UTC）自动检查更新
- **创建Issue**: 检测到更新时自动创建通知Issue

#### 手动触发

1. 进入仓库的 **Actions** 页面
2. 选择 **Smart Kernel Build** 工作流
3. 点击 **Run workflow**
4. 设置参数：
   - **target_version**: 目标内核版本（可选，默认最新）
   - **force_build**: 强制构建（可选）

#### 查看构建结果

- **Artifacts**: 构建产物保留30天
- **Releases**: 自动创建Release并上传
- **Logs**: 失败时自动上传构建日志

---

## 版本管理

### 4.1 当前版本信息

| 组件 | 版本 |
|------|------|
| 内核版本 | 5.4.302 LTS |
| 基础版本 | 5.4.150 |
| KernelSU | susfs-v1.5.5 |
| 目标设备 | Xiaomi Civi 1s |
| 编译工具 | Clang r416183b |

### 4.2 版本文件

#### KERNEL_VERSION

记录当前内核版本：

```bash
cat KERNEL_VERSION
# 输出: 5.4.302
```

#### .kernel_backups/

备份目录结构：

```
.kernel_backups/
├── kernel-backup-5.4.150-20260309_111031/
│   ├── Makefile
│   ├── .config
│   ├── configs/
│   ├── git-status.txt
│   └── git-diff.patch
```

### 4.3 Git标签管理

#### 查看标签

```bash
cd Xiaomi_Kernel_OpenSource-zijin-s-oss
git tag -l "kernel-v*" | sort -V | tail -10
```

#### 创建标签

```bash
./version-manager.sh tag
```

#### 推送标签

```bash
./version-manager.sh push
```

---

## 构建产物

### 5.1 输出文件

#### 文件名格式

```
SukiSU-Kernel-Civi1s-v5.4.302-20260309.zip
```

#### 文件内容

- `Image`: 内核镜像
- `anykernel.sh`: 刷写脚本
- `tools/`: 刷写工具
- `META-INF/`: Magisk相关

#### 安装方法

**方法一：TWRP**
1. 将zip文件传输到设备
2. 进入TWRP Recovery
3. 选择Install → 选择zip文件
4. 滑动确认刷入
5. 重启系统

**方法二：Magisk**
1. 打开Magisk Manager
2. 选择"安装" → "选择并修补一个文件"
3. 选择内核Image文件
4. 刷入生成的patched镜像

### 5.2 Release说明

#### 自动创建的Release包含

- 版本信息
- 构建日期
- 更新内容
- 下载链接

#### Release示例

```markdown
## SukiSU Kernel for Xiaomi Civi 1s

**Kernel Version:** 5.4.302
**Build Date:** 2026-03-09
**Build Number:** 42

### Changes
- Updated kernel to 5.4.302
- Integrated KernelSU with SUSFS
- Applied compatibility patches

### Installation
Flash via TWRP or Magisk

---
*Built automatically by GitHub Actions*
```

---

## 故障排查

### 6.1 更新失败

#### 网络问题

**症状**: 无法下载补丁文件

**解决方案**:
```bash
# 检查网络连接
ping kernel.org

# 使用代理
export https_proxy=http://proxy:port

# 或手动下载补丁
curl -L -o /tmp/patch-5.4.151.xz \
  https://cdn.kernel.org/pub/linux/kernel/v5.x/incr/patch-5.4.150-151.xz
```

#### 补丁冲突

**症状**: git apply失败

**解决方案**:
```bash
# 查看冲突详情
cd Xiaomi_Kernel_OpenSource-zijin-s-oss
git status

# 手动解决冲突
# 编辑冲突文件...

# 继续更新
cd ..
./scripts/smart-update.sh update 5.4.302
```

#### 版本回滚

**症状**: 更新后出现问题

**解决方案**:
```bash
# 列出备份
./scripts/smart-update.sh restore

# 恢复到指定备份
./scripts/smart-update.sh restore kernel-backup-5.4.150-20260309_111031
```

### 6.2 构建失败

#### 依赖缺失

**症状**: 编译报错找不到工具或库

**解决方案**:
```bash
# 检查依赖
./build.sh check_dependencies

# 安装缺失依赖
sudo apt-get update
sudo apt-get install -y bc bison build-essential ccache curl flex \
  g++-multilib gcc-multilib git gnupg gperf \
  liblz4-tool libncurses-dev libssl-dev \
  libxml2-utils lzop rsync squashfs-tools \
  xsltproc zip zlib1g-dev python3 \
  gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
```

#### 编译错误

**症状**: 编译过程中断

**解决方案**:
```bash
# 清理重新编译
./build.sh clean
./build.sh build

# 查看详细日志
cd Xiaomi_Kernel_OpenSource-zijin-s-oss
make -j$(nproc) O=out ARCH=arm64 \
  CC=clang CLANG_TRIPLE=aarch64-linux-gnu- \
  CROSS_COMPILE=aarch64-linux-gnu- \
  2>&1 | tee build.log
```

#### 空间不足

**症状**: No space left on device

**解决方案**:
```bash
# 清理缓存
sudo apt-get clean
rm -rf ~/toolchains/clang/.git

# 清理旧备份
rm -rf .kernel_backups/kernel-backup-5.4.*

# 释放GitHub Actions空间
# 工作流会自动清理不需要的文件
```

---

## 技术细节

### 7.1 补丁应用策略

#### 增量补丁下载

从kernel.org官方镜像下载：

```
https://cdn.kernel.org/pub/linux/kernel/v5.x/incr/patch-5.4.X-Y.xz
```

**优点**:
- 官方来源，安全可靠
- 增量更新，下载量小
- 支持断点续传

#### 补丁应用流程

```bash
# 1. 检查补丁能否干净应用
git apply --check patch-file

# 2. 干净应用
git apply patch-file

# 3. 有冲突时强制应用
git apply --reject --whitespace=fix patch-file

# 4. 清理reject文件
find . -name "*.rej" -delete
```

#### 冲突处理策略

1. **自动检测**: 使用`git apply --check`预检查
2. **强制应用**: 使用`--reject`选项应用补丁
3. **记录冲突**: 记录失败的补丁编号
4. **继续流程**: 失败不中断，继续应用后续补丁
5. **人工审查**: 最后由开发者审查冲突

### 7.2 兼容性保证

#### KernelSU 5.4适配

针对Linux 5.4版本的API差异进行适配：

| 功能 | 状态 | 说明 |
|------|------|------|
| KernelSU核心 | ✅ | 正常工作 |
| SUSFS | ✅ | 正常工作 |
| kernel_umount | ⚠️ | 需要5.11+，已禁用 |
| path_mount | ⚠️ | 需要5.11+，已禁用 |

#### API差异修复

修复的主要API差异：

1. **task_work_add参数**
   ```c
   // 5.11+
   task_work_add(task, work, TWA_RESUME);
   
   // 5.4
   task_work_add(task, work, true);
   ```

2. **pgtable.h位置**
   ```c
   // 5.11+
   #include <asm/pgtable.h>
   
   // 5.4
   #include <asm/pgtable.h>
   ```

3. **strncpy_from_user_nofault**
   ```c
   // 兼容性包装
   #ifndef strncpy_from_user_nofault
   #define strncpy_from_user_nofault strncpy_from_user
   #endif
   ```

---

## 下一步计划

### 8.1 短期目标

- [ ] 优化补丁冲突自动解决算法
- [ ] 添加构建失败自动回滚机制
- [ ] 改进构建速度（ccache配置）
- [ ] 添加更多构建选项（调试模式、优化级别）

### 8.2 中期目标

- [ ] 支持更多LTS版本分支（5.10, 5.15, 6.1）
- [ ] 实现跨版本升级路径
- [ ] 添加自动测试流程
- [ ] 支持多设备构建

### 8.3 长期目标

- [ ] 构建Web界面管理
- [ ] 支持自定义内核配置
- [ ] 实现分布式构建
- [ ] 建立社区贡献流程

---

## 贡献指南

### 如何贡献

1. Fork本仓库
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建Pull Request

### 代码规范

- Shell脚本遵循ShellCheck规范
- 提交信息遵循Conventional Commits
- 添加必要的注释和文档

---

## 致谢

- [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) - KernelSU集成
- [Xiaomi Kernel Source](https://github.com/MiCode/Xiaomi_Kernel_OpenSource) - 内核源码
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3) - 内核打包工具
- [LineageOS Clang](https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b) - 编译工具链

---

## 许可证

本项目采用GPL-2.0许可证。详见[LICENSE](LICENSE)文件。

---

**最后更新**: 2026-03-09  
**维护者**: OpenCode AI Assistant  
**版本**: 2.0.0