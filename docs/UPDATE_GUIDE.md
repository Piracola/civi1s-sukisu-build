# 内核更新流程

## 当前版本信息

| 项目 | 版本 |
|------|------|
| 内核版本 | 5.4.86 |
| SukiSU版本 | v4.1.1 |
| 目标设备 | Xiaomi Civi 1s (zijin) |

## 更新到最新5.4 LTS的步骤

### 1. 检查当前版本

```bash
cd Xiaomi_Kernel_OpenSource-zijin-s-oss
grep -E "^VERSION|^PATCHLEVEL|^SUBLEVEL" Makefile
```

### 2. 查看最新的5.4 LTS版本

访问 https://www.kernel.org/ 查看最新的5.4.x版本（如5.4.280+）

### 3. 运行更新命令

```bash
./build.sh update 5.4.200
```

### 4. 如果补丁失败

```bash
# 查看失败的补丁
cd Xiaomi_Kernel_OpenSource-zijin-s-oss
git status

# 手动解决冲突后继续
git add .
./build.sh build
```

## 注意事项

### 更新前必做

1. **备份当前可工作的版本**
   ```bash
   cp -r Xiaomi_Kernel_OpenSource-zijin-s-oss Xiaomi_Kernel_OpenSource-zijin-s-oss-backup
   ```

2. **确保有足够的磁盘空间** (~30GB)

3. **确保已安装所有依赖**
   ```bash
   sudo apt install -y bc bison build-essential ccache curl flex g++-multilib \
       gcc-multilib git gnupg gperf liblz4-tool libncurses-dev libssl-dev \
       libxml2-utils lzop rsync squashfs-tools xsltproc zip zlib1g-dev \
       python3 python-is-python3 gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
   ```

### 更新中注意

1. **增量更新** - 建议一次更新一个大版本（如86→100，而非86→280）
2. **补丁冲突** - 小米vendor修改可能与upstream冲突
3. **测试编译** - 每次更新后先测试编译成功

### 更新后验证

1. **检查编译是否成功**
2. **检查KernelSU功能是否正常**
3. **测试内核是否可以正常刷入**

## 已知的兼容性问题

### Linux 5.4 vs 新版内核API差异

| 功能 | 5.4状态 | 解决方案 |
|------|---------|----------|
| `task_work_add` | bool参数 | 使用`true`替代`TWA_RESUME` |
| `pgtable.h` | 在asm/ | 条件包含 |
| `seccomp.filter_count` | 不存在 | 条件编译 |
| `path_umount` | 不存在 | 需要5.11+，已禁用 |
| `path_mount` | 不存在 | 需要5.11+，已禁用 |

## 故障排除

### 编译失败

```bash
# 清理后重试
./build.sh clean
./build.sh build
```

### 补丁应用失败

```bash
# 手动应用补丁
cd Xiaomi_Kernel_OpenSource-zijin-s-oss
git apply --reject ../patches/xxx.patch
# 查看被拒绝的部分
find . -name "*.rej"
```

### KernelSU功能异常

```bash
# 重新集成KernelSU
cd Xiaomi_Kernel_OpenSource-zijin-s-oss
rm -rf drivers/kernelsu KernelSU
curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash
bash ../patches/apply-kernelsu-compat.sh
```