# Claude Shop 项目 - Claude Code 配置

## 🤖 每日启动流程（自动执行）

每次开始新的对话session时，Claude将自动执行以下流程：

### 1. 进度检查流程
```
1. 自动读取 DAILY_PROGRESS.md - 了解昨天的进度和遗留问题
2. 自动读取 TASK_CHECKLIST.md - 确定今天的任务优先级  
3. 基于当前项目状态，推荐今天应该重点完成的任务
4. 如果发现阻塞问题，立即提醒并提供解决建议
```

### 2. 每日启动检查清单
- [ ] 检查昨日完成情况和遗留问题
- [ ] 识别今日优先级最高的Critical任务
- [ ] 确认无阻塞问题或提供解决方案
- [ ] 更新项目进度百分比
- [ ] 准备今日开发环境和工具

### 3. 自动化行为规则
**触发条件**: 每次新对话开始时自动执行
**执行顺序**: 
1. Read DAILY_PROGRESS.md (获取昨日状态)
2. Read TASK_CHECKLIST.md (获取任务状态) 
3. 分析并生成今日工作建议
4. 检查并报告任何阻塞问题

---

## 📋 项目上下文记忆

### 项目基本信息
- **项目**: Claude Shop - AWS账号配额管理系统
- **技术栈**: Rails 8.0 + MySQL + Tailwind CSS
- **开发周期**: 42天 (6个阶段)
- **当前状态**: Phase 1 - 项目基础搭建

### 核心文件结构
```
claude-shop-rails/
├── CLAUDE.md                 # 本配置文件
├── PRD.md                   # 产品需求文档
├── PROJECT_ROADMAP.md       # 项目路线图
├── DAILY_PROGRESS.md        # 每日进度追踪
├── TASK_CHECKLIST.md        # 任务检查清单
├── .claude/
│   └── context.md           # 详细上下文记忆
├── app/                     # Rails应用代码
├── config/                  # 配置文件
└── db/                      # 数据库相关
```

### 开发重点提醒
1. **安全第一**: AWS密钥必须加密存储，所有操作需审计日志
2. **性能目标**: 页面加载<3秒，API响应<1秒
3. **测试覆盖**: 关键功能100%测试覆盖率
4. **代码质量**: 遵循Rails最佳实践，使用RuboCop检查

---

## 🔄 工作流程自动化

### 开发阶段切换检查
当完成一个阶段时，自动检查：
- [ ] 所有Critical任务是否完成
- [ ] 里程碑验收标准是否达成
- [ ] 是否存在技术债务需要处理
- [ ] 下一阶段的准备工作是否就绪

### 问题追踪提醒
自动检查并提醒：
- 超过24小时未解决的阻塞问题
- 偏离计划超过2天的任务
- 测试覆盖率低于80%的模块
- 性能指标不达标的功能

### 质量门禁检查
每个阶段完成前自动验证：
- 代码质量评级达到A级
- 安全扫描无高危漏洞
- 所有单元测试通过
- 功能验收测试通过

---

## 📊 进度监控配置

### 自动进度更新
- 任务完成时自动更新TASK_CHECKLIST.md
- 每日结束时提醒更新DAILY_PROGRESS.md
- 里程碑达成时自动更新PROJECT_ROADMAP.md

### 预警机制
- 任务延期超过1天：黄色预警
- 任务延期超过3天：红色预警
- 里程碑风险：提前5天预警

---

## 🛠️ 开发工具集成

### 推荐的每日工作流
1. **晨会检查** (自动执行)
   - 检查昨日进度和今日计划
   - 识别优先级任务和阻塞问题
   
2. **开发过程**
   - 使用TodoWrite跟踪当前任务进度
   - 遇到问题立即记录到问题追踪系统
   
3. **日终总结**
   - 更新DAILY_PROGRESS.md
   - 标记完成的任务
   - 记录遇到的问题和解决方案

### Claude Code工具使用优先级
1. **Read**: 获取项目状态和代码内容
2. **TodoWrite**: 跟踪当前工作进度
3. **Write/Edit**: 编写和修改代码文件
4. **Bash**: 执行开发环境相关命令

## 🗄️ 数据库查询手册

### 数据库连接
使用Docker连接到MySQL数据库：
```bash
docker exec claude_shop_mysql mysql -u root -p'claude_shop_root_2024' claude_shop_development
```

### 常用查询

#### 1. 查询特定账号信息
```sql
-- 查找账号基本信息
SELECT id, name, account_id, status FROM aws_accounts WHERE name = 'f-01';

-- 查询账号的所有配额
SELECT 
    qd.claude_model_name,
    qd.quota_type,
    aq.current_quota,
    qd.default_value,
    aq.quota_level,
    aq.sync_status
FROM account_quotas aq 
JOIN quota_definitions qd ON aq.quota_definition_id = qd.id 
WHERE aq.aws_account_id = [ACCOUNT_ID]
ORDER BY qd.claude_model_name, qd.quota_type;
```

#### 2. 配额级别判断逻辑
- **low**: current_quota < default_value
- **medium**: current_quota = default_value  
- **high**: current_quota > default_value

#### 3. f-01账号配额详情 (最后更新: 2025-07-31)
```
账号ID: 8, 名称: f-01, AWS账号: 730335638719

配额详情:
- Claude 3.5 Sonnet V1 RPM: 1 (默认50) → low 🔴
- Claude 3.5 Sonnet V1 TPM: 400000 (默认400000) → medium 🔵
  → 最终显示: 🔴 low (受限于RPM低配额)

- Claude 3.5 Sonnet V2 RPM: 50 (默认50) → medium 🔵  
- Claude 3.5 Sonnet V2 TPM: 400000 (默认400000) → medium 🔵
  → 最终显示: 🔵 medium (两项都是标准配额)

- Claude 3.7 Sonnet V1 RPM: 250 (默认250) → medium 🔵
- Claude 3.7 Sonnet V1 TPM: 1000000 (默认1000000) → medium 🔵
- Claude 3.7 Sonnet V1 TPD: 5400000 (默认720000000) → low 🔴
  → 最终显示: 🔴 low (受限于TPD低配额)

- Claude 4 Sonnet V1 RPM: 2 (默认200) → low 🔴
- Claude 4 Sonnet V1 TPM: 200000 (默认200000) → medium 🔵  
- Claude 4 Sonnet V1 TPD: 5400000 (默认144000000) → low 🔴
  → 最终显示: 🔴 low (受限于RPM和TPD低配额)
```

#### 4. available_models_with_levels 显示逻辑
基于每个模型的**最低配额级别**显示（木桶效应 - 最薄弱环节决定整体性能）：
- 如果模型有任何low级别配额 → 显示红色（受限于低配额）
- 如果模型有任何medium级别配额（无low） → 显示蓝色  
- 如果模型只有high级别配额 → 显示绿色

---

**配置生效**: 立即生效，每次新对话自动应用
**最后更新**: 2025-07-31
**下次评审**: Phase 3完成后