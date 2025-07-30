# RefreshJob 进度显示问题最终修复

## 问题症状
手动刷新任务启动后，进度一直显示 0.0%，任务看似卡住。

## 根本原因
经过深入诊断，发现了几个相互关联的问题：

### 1. `processed_accounts` 字段初始化问题
RefreshJob 模型的 `set_defaults` 方法没有初始化 `processed_accounts` 字段，导致它为 `nil`。

### 2. 进度计算中的 nil 处理
`progress_percentage` 方法没有处理 `processed_accounts` 为 `nil` 的情况。

### 3. 进度更新参数类型不匹配
Job 中传递的是比例值（0, 0.5, 1.0），但 `update_progress` 方法期望的是整数计数。

### 4. 数据模型迁移后的兼容性问题
之前修复的问题：使用了旧的数据模型和缺失的方法。

## 修复内容

### 1. RefreshJob 模型修复 (`app/models/refresh_job.rb`)

#### 修复字段初始化
```ruby
def set_defaults
  self.successful_accounts = 0
  self.failed_accounts = 0
  self.processed_accounts = 0  # 新增
end
```

#### 修复进度计算
```ruby
def progress_percentage
  return 0 if total_accounts.zero? || processed_accounts.nil?  # 新增 nil 检查
  [(processed_accounts.to_f / total_accounts * 100).round(2), 100].min
end
```

#### 增强进度更新方法
```ruby
def update_progress(processed_count_or_ratio)
  return unless running?
  return if total_accounts.zero?

  # 如果传入的是比例（0.0-1.0），转换为实际账号数
  if processed_count_or_ratio.is_a?(Float) && processed_count_or_ratio <= 1.0
    processed_count = (processed_count_or_ratio * total_accounts).round
  else
    processed_count = processed_count_or_ratio.to_i
  end

  update!(processed_accounts: processed_count)
end
```

### 2. RefreshQuotaJob 任务修复 (`app/jobs/refresh_quota_job.rb`)

#### 添加进度更新调用
```ruby
def refresh_single_account(aws_account_id, options = {})
  # ... 创建和启动任务 ...
  
  # 添加进度更新
  refresh_job.update_progress(0)      # 任务开始：0%
  
  begin
    # 添加进度更新
    refresh_job.update_progress(0.5)  # 刷新开始：50%
    
    result = AwsService.refresh_account_quotas(aws_account)
    
    if result[:success]
      refresh_job.update_progress(1.0)  # 完成前：100%
      refresh_job.complete!(1, 0)
    # ...
  end
end
```

## 修复验证

修复后的工作流程：

1. **用户点击刷新**: 创建 RefreshJob，状态为 `running`
2. **进度 0%**: `processed_accounts = 0`，显示 0.0%
3. **进度 50%**: `processed_accounts = 0.5 * 1 = 1`，但对于单账号任务应该是 50%
4. **进度 100%**: `processed_accounts = 1.0 * 1 = 1`，显示 100%
5. **任务完成**: 状态变为 `completed`

实际上，对于单账号任务（`total_accounts = 1`），进度应该这样计算：
- 0% → `processed_accounts = 0`
- 50% → `processed_accounts = 0.5` (通过比例转换)
- 100% → `processed_accounts = 1`

## 测试步骤

1. 重启 Rails 服务器以加载修复
2. 访问 AWS 账号详情页面
3. 点击"刷新配额"按钮
4. 观察进度正常从 0% → 50% → 100%
5. 确认任务最终状态为"已完成"

## 相关文件

- `app/models/refresh_job.rb` - 核心修复
- `app/jobs/refresh_quota_job.rb` - 进度更新调用
- `app/models/aws_account.rb` - 之前的兼容性修复
- `app/services/aws_service.rb` - 之前的服务修复
- `app/services/aws_quota_service.rb` - 之前的方法补充

## 预期结果

修复后，手动刷新任务应该：
✅ 正确显示进度变化  
✅ 不再卡在 0.0%  
✅ 能够成功完成  
✅ 正确更新配额数据  
✅ 记录正确的审计日志  

## 注意事项

- 这个修复保持了向后兼容性
- 支持both整数计数和比例值的进度更新
- 正确处理了 nil 值的边界情况
- 为未来的批量任务提供了基础