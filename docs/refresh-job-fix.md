# 手动刷新任务进度卡在 0.0% 问题修复

## 问题描述
手动刷新配额任务执行时，进度一直显示 0.0%，任务无法正常完成。

## 根本原因分析
1. **数据模型不匹配**: `AwsService.refresh_account_quotas` 方法使用了旧的 `Quota` 模型和字段结构，但系统已迁移到新的 `AccountQuota` 和 `QuotaDefinition` 模型
2. **缺失的 quotas 关联**: AwsAccount 模型缺少 `quotas` 方法的别名
3. **缺失的服务方法**: AwsQuotaService 缺少 `quota_key` 和 `evaluate_quota_level` 方法
4. **进度更新缺失**: RefreshQuotaJob 没有正确调用进度更新方法

## 修复内容

### 1. AwsAccount 模型 (`app/models/aws_account.rb`)
```ruby
# 添加向后兼容的别名
alias_method :quotas, :account_quotas
```

### 2. AwsService 服务 (`app/services/aws_service.rb`)
完全重写了 `refresh_account_quotas` 方法：
- 使用新的 `AwsQuotaService.refresh_all_quotas` 方法
- 正确处理 AccountQuota 模型
- 改进错误处理和状态更新

### 3. AwsQuotaService 服务 (`app/services/aws_quota_service.rb`)
添加了缺失的方法：
- `CLAUDE_MODELS` 常量：定义 Claude 模型配置
- `quota_key(model_name, quota_type)`: 生成配额键
- `evaluate_quota_level(quota_type, current_value, default_value)`: 评估配额等级
- `quota_types_for_model(model_name)`: 获取模型的配额类型
- `quota_description(quota_key)`: 获取配额描述

### 4. RefreshQuotaJob 任务 (`app/jobs/refresh_quota_job.rb`)
添加了进度更新：
- 任务开始时：`update_progress(0)`
- 刷新进行中：`update_progress(0.5)`
- 完成前：`update_progress(1)`
- 修复了 `includes(:quotas)` 为 `includes(:account_quotas)`

### 5. AuditLog 模型 (`app/models/audit_log.rb`)
添加了缺失的 `details` 方法：
```ruby
def details
  metadata&.dig('details') || ''
end
```

## 修复验证

修复后，手动刷新任务应该：
1. 正确显示进度从 0% → 50% → 100%
2. 成功刷新账号配额数据
3. 正确记录审计日志
4. 更新账号连接状态

## 测试步骤

1. 访问 AWS 账号详情页面
2. 点击"刷新配额"按钮
3. 观察任务进度正常变化
4. 确认配额数据成功更新
5. 检查审计日志记录正确

## 相关文件

- `app/models/aws_account.rb` - 添加 quotas 别名
- `app/models/audit_log.rb` - 添加 details 方法
- `app/services/aws_service.rb` - 重写刷新方法
- `app/services/aws_quota_service.rb` - 添加缺失方法
- `app/jobs/refresh_quota_job.rb` - 添加进度更新
- `app/models/account_quota.rb` - 已有的 refresh! 方法
- `app/models/quota_definition.rb` - 已有的 display_name 方法

## 注意事项

- 所有修改都保持了向后兼容性
- 新的刷新逻辑使用了更现代的数据结构
- 错误处理更加完善
- 进度跟踪更加准确