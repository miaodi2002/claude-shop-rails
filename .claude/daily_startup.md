# 每日启动检查脚本

## 🚀 Claude 每日启动执行流程

当检测到新的对话session开始时，Claude将按以下顺序自动执行：

### Step 1: 读取昨日进度
```markdown
Action: Read DAILY_PROGRESS.md
Purpose: 
- 了解昨天完成的任务
- 识别遗留的问题
- 确认当前项目阶段
- 检查是否有阻塞问题
```

### Step 2: 分析任务状态  
```markdown
Action: Read TASK_CHECKLIST.md
Purpose:
- 统计总体完成进度
- 识别Critical优先级的待办任务
- 确认任务依赖关系
- 计算里程碑完成度
```

### Step 3: 生成今日建议
```markdown
Action: 分析并输出建议
Content:
- 📊 当前进度报告 (X%完成)
- 🎯 今日优先级任务清单 (3-5个Critical任务)
- ⚠️ 阻塞问题提醒 (如有)
- 📋 预估完成时间和里程碑状态
- 💡 开发建议和注意事项
```

### Step 4: 环境状态检查
```markdown
Action: 准备开发环境
Check:
- 项目文件结构完整性
- 关键配置文件存在性
- 开发工具链状态
- 依赖关系验证
```

## 📝 输出模板

每次启动时，Claude将输出以下格式的报告：

```
🌅 Claude Shop 每日启动报告 - YYYY-MM-DD

📊 项目进度概览:
- 总体进度: X% (阶段X/6)
- 里程碑状态: MX [状态]
- 昨日完成: X个任务
- 今日计划: X个任务

🎯 今日优先任务 (Critical):
1. [T00X] 任务名称 - 预估耗时
2. [T00X] 任务名称 - 预估耗时  
3. [T00X] 任务名称 - 预估耗时

⚠️ 需要注意的问题:
- 问题1: 描述和建议解决方案
- 问题2: 描述和建议解决方案

💡 今日开发建议:
- 技术建议1
- 注意事项2
- 最佳实践3

✅ 准备开始工作!
```

## 🔄 自动化触发规则

### 触发条件
1. **新对话检测**: 检测到session重新开始
2. **时间条件**: 距离上次启动检查超过8小时
3. **手动触发**: 用户明确要求进行启动检查
4. **阶段切换**: 检测到项目阶段发生变化

### 执行频率
- **每日首次对话**: 必须执行
- **同日后续对话**: 简化版检查
- **跨天对话**: 完整启动流程
- **紧急情况**: 立即执行检查

### 跳过条件
- 用户明确表示跳过启动检查
- 正在处理紧急问题
- 执行特定的独立任务

## 🎛️ 个性化配置

### 提醒偏好设置
```yaml
reminder_level: detailed  # simple, detailed, comprehensive
focus_mode: critical_only # all_tasks, critical_only, custom
problem_alert: immediate  # immediate, daily, weekly
progress_detail: full     # minimal, summary, full
```

### 工作时间设置
```yaml
work_hours:
  start: 09:00
  end: 18:00
  timezone: Asia/Shanghai
  weekend_work: false
```

### 通知规则
```yaml
notifications:
  task_overdue: true
  milestone_risk: true
  dependency_block: true
  progress_report: daily
```

## 📋 检查清单验证

每次执行启动流程后，验证以下项目：

### 文件完整性检查
- [ ] DAILY_PROGRESS.md 存在且可读取
- [ ] TASK_CHECKLIST.md 存在且格式正确
- [ ] PROJECT_ROADMAP.md 里程碑信息最新
- [ ] .claude/context.md 上下文信息完整

### 数据有效性检查  
- [ ] 进度百分比计算正确
- [ ] 任务优先级标记准确
- [ ] 依赖关系逻辑合理
- [ ] 时间估算相对准确

### 提醒准确性检查
- [ ] 阻塞问题识别正确
- [ ] 优先级排序合理
- [ ] 建议方案可执行
- [ ] 预警提醒及时

## 🔧 故障处理

### 常见问题处理
1. **文件读取失败**: 提示文件路径或权限问题
2. **格式解析错误**: 提示修复文档格式
3. **数据不一致**: 建议同步各文档状态
4. **依赖循环**: 提示任务依赖关系错误

### 降级方案
- 文件无法读取 → 使用缓存信息 + 提醒用户
- 格式错误 → 基础功能继续，详细功能降级
- 数据缺失 → 询问用户当前状态并手动更新

---

**创建时间**: 2025-07-25 12:50
**适用范围**: Claude Shop项目
**维护人**: Claude Code Assistant