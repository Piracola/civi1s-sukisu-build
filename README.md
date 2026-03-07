# SukiSU Kernel for Xiaomi Civi 1s

基于小米zijin-s-oss内核源码，集成SukiSU-Ultra的Android内核。

## 项目结构

```
civi1s-sukisu-build/
├── build.sh                    # 主构建脚本
├── patches/
│   ├── 0001-kernelsu-config.patch      # 内核配置补丁
│   └── apply-kernelsu-compat.sh        # Linux 5.4兼容性修复脚本
└── .github/workflows/
    └── build.yml               # GitHub Actions工作流
```

## 快速开始

```bash
# 完整构建（从零开始）
./build.sh full

# 仅编译（已有源码）
./build.sh build

# 更新内核版本
./build.sh update 5.4.200

# 清理输出
./build.sh clean
```

## 已测试版本

| 内核版本 | SukiSU版本 | 状态 |
|---------|-----------|------|
| 5.4.86  | v4.1.1    | ✅ 可用 |

## 兼容性说明

### Linux 5.4适配修复

SukiSU-Ultra面向更新版本的内核，以下功能已适配：

| 功能 | 状态 | 说明 |
|-----|------|------|
| KernelSU核心 | ✅ | 正常工作 |
| SUSFS | ✅ | 正常工作 |
| kernel_umount | ⚠️ | 需要5.11+，已禁用 |
| path_mount | ⚠️ | 需要5.11+，已禁用 |

### 修复的API差异

1. `TWA_RESUME` → `true` (task_work_add参数)
2. `pgtable.h`位置变化
3. `strncpy_from_user_nofault`兼容性
4. `seccomp`结构体差异
5. SELinux `filename_trans`结构变化
6. `fsnotify_ops`回调签名

## 内核更新流程

```bash
# 1. 更新到指定版本（如5.4.200）
./build.sh update 5.4.200

# 2. 如果补丁失败，手动解决后继续
cd Xiaomi_Kernel_OpenSource-zijin-s-oss
git status  # 查看冲突

# 3. 测试编译
./build.sh build
```

## 注意事项

### 更新内核版本

1. **增量更新** - 建议一次更新一个大版本
2. **保留备份** - 更新前确保有可工作的版本
3. **检查冲突** - 小米vendor修改可能与upstream冲突

### 构建环境

- Ubuntu 20.04+ 或 Debian 11+
- 至少16GB RAM
- 约30GB磁盘空间

## 输出文件

构建完成后生成：
```
SukiSU-Kernel-Civi1s-YYYYMMDD.zip
```

可通过Magisk或TWRP刷入。

## 致谢

- [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra)
- [Xiaomi Kernel Source](https://github.com/MiCode/Xiaomi_Kernel_OpenSource)
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3)