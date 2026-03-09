# 手动解决内核补丁冲突 - 完整指南

## 当前状态
- 内核版本：5.4.150 → 5.4.151（第一个补丁）
- 冲突文件：`drivers/net/ethernet/stmicro/stmmac/stmmac_main.c:4880`
- 冲突类型：补丁应用失败

## 冲突分析

### 查看冲突内容

**方法1：查看reject文件**（如果有）
```bash
cat drivers/net/ethernet/stmicro/stmmac/stmmac_main.c.rej
```

**方法2：查看补丁内容**
```bash
grep -A 20 "stmmac_resume" /tmp/patch-5.4.151
```

**方法3：查看源文件**
```bash
sed -n '4870,4900p' drivers/net/ethernet/stmicro/stmmac/stmmac_main.c
```

### 冲突原因分析

补丁试图修改`stmmac_resume`函数，但：
1. 小米可能有定制修改
2. 函数结构可能不同
3. 行号不匹配

### 手动解决步骤

#### Step 1: 查看补丁想要做什么

```bash
# 查看补丁中的修改
grep -B 5 -A 10 "stmmac_resume" /tmp/patch-5.4.151
```

#### Step 2: 找到源文件中的对应位置

```bash
# 在源文件中搜索函数
grep -n "stmmac_resume" drivers/net/ethernet/stmicro/stmmac/stmmac_main.c
```

#### Step 3: 手动应用修改

使用文本编辑器打开文件：
```bash
vim drivers/net/ethernet/stmicro/stmmac/stmmac_main.c
```

应用补丁中的修改，保留小米的关键代码。

#### Step 4: 验证修改

```bash
# 编译测试
make -j8 drivers/net/ethernet/stmicro/stmmac/stmmac_main.o
```

#### Step 5: 更新版本号

```bash
sed -i 's/^SUBLEVEL = .*/SUBLEVEL = 151/' Makefile
```

#### Step 6: 清理并继续

```bash
rm -f drivers/net/ethernet/stmicro/stmmac/stmmac_main.c.rej
git add drivers/net/ethernet/stmicro/stmmac/stmmac_main.c
```

## 决策原则

### 何时接受upstream修改

1. **安全修复**：必须接受
   - Spectre/Meltdown缓解
   - 安全漏洞修复

2. **Bug修复**：应该接受
   - 已知的bug修复
   - 性能问题修复

3. **API改进**：可以接受
   - 向后兼容的API
   - 更安全的实现

### 何时保留小米版本

1. **Vendor特定功能**
   - 小米特有的硬件支持
   - 定制的电源管理

2. **性能优化**
   - 小米的性能调优
   - 设备特定的优化

3. **API不兼容**
   - 可能导致其他代码失效
   - 需要大规模修改

## 手动解决示例

### 示例：stmmac_main.c冲突

**补丁内容**（假设）：
```diff
-	phylink_mac_change(priv->phylink, true);
+	phylink_mac_change(priv->phylink, false);
```

**解决方法**：

1. 理解改动：将`true`改为`false`
2. 评估影响：影响网络唤醒功能
3. 查看小米代码：
```bash
grep -B 3 -A 3 "phylink_mac_change" drivers/net/ethernet/stmicro/stmmac/stmmac_main.c
```

4. 决策：
   - 如果小米有特殊需求 → 保留`true`
   - 如果是bug修复 → 改为`false`

5. 手动修改：
```bash
vim +/phylink_mac_change drivers/net/ethernet/stmicro/stmmac/stmmac_main.c
# 手动修改参数
```

6. 测试：
```bash
# 编译测试
make drivers/net/ethernet/stmicro/stmmac/stmmac_main.o
```

## 完整的手动解决流程

```bash
#!/bin/bash
# 对于每个补丁

# 1. 尝试应用
git apply --check /tmp/patch-5.4.XXX

# 2. 如果失败，查看冲突
git apply --reject /tmp/patch-5.4.XXX

# 3. 查看reject文件
find . -name "*.rej" -exec cat {} \;

# 4. 手动解决每个冲突
vim <conflicted-file>

# 5. 清理reject文件
find . -name "*.rej" -delete

# 6. 更新版本号
sed -i 's/SUBLEVEL = .*/SUBLEVEL = XXX/' Makefile

# 7. Git提交
git add -A
git commit -m "fix: manually resolve conflicts for 5.4.XXX"

# 8. 继续下一个补丁
```

## 时间估算

对于从5.4.150到5.4.302的更新：
- 总补丁数：152个
- 每个补丁预计时间：5-10分钟（如果有冲突）
- 预计总时间：**2-4小时**

## 自动化辅助

我已经创建的工具：
- `scripts/incremental-update.sh` - 增量更新脚本
- `scripts/fix-conflicts.sh` - 冲突分析工具

## 建议

鉴于这是大量手动工作，我建议：

### 方案A：增量更新（当前执行）
- ✅ 正在执行
- ⏰ 需要时间
- ✅ 最正确

### 方案B：选择性更新
- 只应用安全补丁
- 跳过其他补丁
- 更快但不够完整

### 方案C：保持5.4.150
- 只集成KernelSU
- 不更新内核版本
- 最稳定

你想要继续手动解决这152个补丁吗？还是采用其他方案？