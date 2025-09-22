# AWS费用管理功能 - 任务检查清单

## 🎯 项目概述
基于Rails最佳实践，为Claude Shop添加AWS账号费用管理功能，支持管理员查看最近2周的每日费用数据。

### 📋 核心需求
- **用户权限**: 仅管理员可访问
- **数据范围**: 每个账号最近2周的每日费用
- **费用精度**: USD货币，保留2位小数  
- **更新方式**: 手动触发（单账号/批量）
- **错误处理**: 重试1次，显示AWS具体错误信息
- **前端展示**: 柱状图 + 日期范围选择

## 📈 开发进度总览
- **Phase 1**: 基础设施搭建 (0/5) ⚪
- **Phase 2**: Model层实现 (0/3) ⚪  
- **Phase 3**: 服务层实现 (0/3) ⚪
- **Phase 4**: 后台任务实现 (0/3) ⚪
- **Phase 5**: 控制器和路由 (0/5) ⚪
- **Phase 6**: 前端界面 (0/5) ⚪
- **Phase 7**: 测试和优化 (0/6) ⚪

**总进度**: 0/30 (0%) 🔴

---

## Phase 1: 基础设施搭建 - 更新依赖和数据库

### ✅ 核心依赖安装
- [ ] **Critical** 更新Gemfile，添加aws-sdk-costexplorer和parallel gems
  - 添加 `gem 'aws-sdk-costexplorer'`
  - 添加 `gem 'parallel'` 
  - 可选添加 `gem 'chartkick'`
  - 运行 `bundle install`

### 📊 数据库架构设计  
- [ ] **Critical** 创建DailyCost数据库迁移文件
  - 表结构：aws_account_id, date, cost_amount, currency
  - 索引：唯一键(aws_account_id, date)，日期索引
  - 外键约束：关联aws_accounts表

- [ ] **Critical** 创建CostSyncLog数据库迁移文件  
  - 表结构：aws_account_id, status, sync_type, error_message, 时间字段
  - 枚举：status(pending/success/failed/in_progress), sync_type(single/batch)
  - 索引：状态索引，创建时间索引

- [ ] **Critical** 运行数据库迁移并验证表结构
  - 执行 `rails db:migrate`
  - 验证表创建成功和索引完整性
  - 检查外键约束正确设置

---

## Phase 2: Model层实现 - 创建数据模型

### 💎 核心数据模型
- [ ] **Critical** 实现DailyCost模型（关联、验证、作用域）
  - belongs_to :aws_account 关联
  - 验证：date唯一性, cost_amount数值验证, currency格式
  - 作用域：recent_weeks, by_date_range, ordered_by_date
  - 辅助方法：formatted_cost, total_for_period

- [ ] **Critical** 实现CostSyncLog模型（枚举、关联、辅助方法）
  - belongs_to :aws_account (可选关联)
  - 枚举：status和sync_type
  - 验证：single_account时必须有aws_account
  - 辅助方法：duration, success_rate

- [ ] **Important** 为AwsAccount模型添加费用相关关联
  - has_many :daily_costs 关联
  - has_many :cost_sync_logs 关联  
  - 费用统计相关方法

---

## Phase 3: 服务层实现 - AWS API集成

### 🔌 AWS服务集成
- [ ] **Critical** 创建AwsCostExplorerService服务类
  - 初始化方法：设置AWS客户端连接
  - 类方法：fetch_daily_costs, batch_sync_all_accounts
  - 凭证管理：安全使用aws_account的access_key和secret_key

- [ ] **Critical** 实现AWS Cost Explorer API调用和重试机制
  - get_cost_and_usage API调用
  - 重试机制：最多重试1次，间隔2秒
  - 参数设置：时间范围、粒度(DAILY)、指标(UnblendedCost)

- [ ] **Critical** 实现费用数据解析和错误处理
  - 解析API响应：提取日期和费用数据
  - 异常处理：AWS API错误转换为友好错误信息
  - 数据验证：确保费用数据格式正确

---

## Phase 4: 后台任务实现 - Sidekiq Jobs

### ⚡ 异步任务处理
- [ ] **Critical** 创建CostSyncJob单账号同步任务
  - 任务参数：account_id, 可选date_range
  - 同步流程：创建日志→获取数据→更新数据库→更新日志状态
  - 错误处理：捕获异常并记录到sync_log

- [ ] **Critical** 创建BatchCostSyncJob批量同步任务
  - 并行处理：使用Parallel gem处理多个账号
  - 容错机制：个别账号失败不影响整体批量操作
  - 批量日志：创建batch_all类型的同步日志

- [ ] **Important** 实现并行处理和容错机制
  - 线程池配置：最多5个并行线程
  - 错误隔离：单个账号失败不中断其他账号处理
  - 日志记录：详细记录每个账号的同步结果

---

## Phase 5: 控制器和路由 - Admin接口

### 🎮 管理员接口
- [ ] **Critical** 创建Admin::CostsController控制器
  - 继承Admin::BaseController确保权限验证
  - before_action设置：set_aws_account用于需要账号参数的操作

- [ ] **Critical** 实现费用管理主页和详情页
  - index: 账号列表+分页，最近同步记录显示
  - show: 单账号费用详情，图表数据，同步历史

- [ ] **Critical** 实现同步操作接口
  - sync_account: 单账号费用同步，触发CostSyncJob
  - batch_sync: 批量账号同步，触发BatchCostSyncJob

- [ ] **Important** 实现图表数据API和同步状态API  
  - chart_data: 返回指定日期范围的费用数据JSON
  - sync_status: 返回最近同步状态，供前端轮询更新

- [ ] **Important** 配置路由和权限验证
  - 嵌套路由：admin namespace下的costs资源
  - RESTful设计：member和collection路由分类
  - 权限继承：确保只有管理员可访问

---

## Phase 6: 前端界面 - 用户体验

### 🎨 用户界面设计
- [ ] **Critical** 创建费用管理主页视图
  - 网格布局：账号卡片展示，响应式设计
  - 操作按钮：单账号同步、批量同步
  - 状态面板：实时显示最近同步记录

- [ ] **Critical** 创建单账号详情页视图  
  - 概览面板：总费用、日均费用、最后同步时间
  - 图表区域：Canvas元素用于Chart.js渲染
  - 数据表格：同步历史记录表格

- [ ] **Critical** 集成Chart.js实现交互式柱状图
  - 图表初始化：柱状图配置，Y轴货币格式化
  - 数据加载：异步获取chart_data API数据
  - 图表更新：支持数据变更时的平滑更新

- [ ] **Important** 实现实时同步状态更新功能
  - JavaScript轮询：每5秒获取sync_status API
  - 状态渲染：动态更新同步记录显示
  - 错误显示：展示同步失败的具体错误信息

- [ ] **Important** 添加日期范围选择和图表更新功能
  - 日期选择器：HTML5 date input控件
  - 参数传递：start_date和end_date查询参数  
  - 图表刷新：updateChart函数重新加载数据

---

## Phase 7: 测试和优化 - 质量保证

### 🧪 测试覆盖
- [ ] **Critical** 编写Model层单元测试
  - DailyCost: 关联测试、验证测试、作用域测试
  - CostSyncLog: 枚举测试、辅助方法测试
  - AwsAccount: 新增关联的测试覆盖

- [ ] **Critical** 编写Service层测试
  - AwsCostExplorerService: API调用mock测试  
  - 重试机制测试：模拟网络失败场景
  - 错误处理测试：AWS异常转换测试

- [ ] **Important** 编写Controller层集成测试
  - 权限测试：确保只有管理员可访问
  - 路由测试：所有endpoint正确响应
  - JSON API测试：chart_data和sync_status接口

- [ ] **Important** 编写Job层测试
  - CostSyncJob: 成功和失败场景测试
  - BatchCostSyncJob: 并行处理和容错测试
  - Sidekiq集成测试：任务队列和执行

### 🚀 性能和用户体验优化
- [ ] **Important** 性能测试和数据库查询优化
  - 索引效果验证：查询执行计划分析
  - N+1查询检查：includes优化关联查询
  - 分页性能测试：大量数据场景下的响应时间

- [ ] **Nice-to-have** 用户体验测试和界面优化
  - 响应式测试：移动端适配验证  
  - 交互测试：按钮状态、加载提示
  - 错误处理UX：用户友好的错误信息展示

---

## 📝 验收标准

### 功能完整性检查
- ✅ 单账号费用同步：手动触发成功，数据正确保存
- ✅ 批量费用同步：并行处理，个别失败不影响整体  
- ✅ 实时状态监控：同步状态实时更新，错误信息清晰展示
- ✅ 交互式图表：柱状图正确展示，日期范围选择生效
- ✅ 权限控制：只有管理员可访问，权限验证正确

### 技术质量检查
- ✅ Rails最佳实践：遵循约定，代码结构清晰
- ✅ 错误处理完善：AWS API错误正确处理和展示
- ✅ 性能优化：数据库查询优化，响应时间<3秒
- ✅ 测试覆盖：关键功能100%测试覆盖
- ✅ 安全考虑：AWS凭证安全处理，CSRF保护

### 用户体验检查  
- ✅ 界面友好：响应式设计，操作直观
- ✅ 实时反馈：操作状态实时显示，加载提示清晰
- ✅ 错误提示：错误信息用户友好，操作指导明确
- ✅ 性能流畅：页面加载快速，交互响应及时

---

## 🔧 技术债务和改进点

### 短期改进 (本期完成)
- [ ] 添加费用数据导出功能 (CSV/Excel)
- [ ] 实现费用预警机制 (超出阈值通知)
- [ ] 添加费用趋势分析 (周环比、月环比)

### 长期规划 (下期考虑)
- [ ] 自动定时同步任务 (Cron Job)
- [ ] 费用预测功能 (基于历史数据)
- [ ] 多维度费用分析 (按服务分类)
- [ ] 费用报表系统 (PDF生成)

---

## 📊 里程碑时间计划

| 阶段 | 预计耗时 | 关键交付物 | 验收标准 |
|------|----------|-----------|----------|
| Phase 1 | 1天 | 数据库结构 | 迁移成功执行 |
| Phase 2 | 1天 | 数据模型 | 单元测试通过 |
| Phase 3 | 2天 | AWS API集成 | 服务测试通过 |  
| Phase 4 | 1天 | 后台任务 | 任务执行成功 |
| Phase 5 | 2天 | 管理员接口 | 接口功能完整 |
| Phase 6 | 2天 | 前端界面 | 用户体验良好 |
| Phase 7 | 1天 | 测试优化 | 质量标准达成 |

**总计**: 10个工作日

---

# 📊 Claude Shop 项目整体进度

## 🎯 总体进度
- **总任务数**: 75个（Claude Shop主项目 + AWS费用管理功能）
- **已完成**: 36个 (48.0%) Claude Shop主功能
- **AWS费用功能**: 30个 (0.0%) 新增功能
- **进行中**: 0个
- **待开始**: 39个

## 各项目状态
### Claude Shop 主项目 ✅ Phase 1-3 完成
- **Phase 0**: 环境搭建 ✅ 100%
- **Phase 1**: 核心功能实现 ✅ 100%
- **Phase 2**: 管理员后台 ✅ 82.6%
- **Phase 3**: 公开展示系统 ✅ 100%
- **Phase 4**: 测试与部署 ⏳ 0%

### AWS费用管理功能 🆕 新增项目
- **Phase 1**: 基础设施搭建 ⏳ 0%
- **Phase 2**: Model层实现 ⏳ 0%
- **Phase 3**: 服务层实现 ⏳ 0%
- **Phase 4**: 后台任务实现 ⏳ 0%
- **Phase 5**: 控制器和路由 ⏳ 0%
- **Phase 6**: 前端界面 ⏳ 0%
- **Phase 7**: 测试和优化 ⏳ 0%

## 重大里程碑成就 🎉
✅ **配额系统完全重构**: 2025-07-27  
✅ **AWS配额API验证**: 2025-07-29  
✅ **AWS账号创建优化**: 2025-07-30  
✅ **完整管理员认证系统**: 2025-07-30  
✅ **公开展示系统上线**: 2025-07-30  
🆕 **AWS费用管理功能设计完成**: 2025-08-26

## 下阶段待办（高优先级）
1. **AWS费用管理功能开发** ⭐ 新增最高优先级
   - Phase 1-7: 完整费用管理系统开发
   - 预计耗时: 10个工作日
   - 技术栈: Rails + AWS Cost Explorer API + Chart.js

2. **Claude Shop测试与部署** ⭐ 持续优先级
   - Phase 4: 单元测试和集成测试
   - 生产环境配置和CI/CD
   - 全流程测试验证

---

**最后更新**: 2025-08-26  
**负责人**: Claude Assistant  
**优先级**: High Priority 🔴  
**当前状态**: AWS费用管理功能设计完成，准备开始实施 🚀