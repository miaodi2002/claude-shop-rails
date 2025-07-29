# frozen_string_literal: true

class BulkRefreshJob < ApplicationJob
  queue_as :high_priority
  
  def perform(refresh_job_id)
    refresh_job = RefreshJob.find(refresh_job_id)
    
    # 更新任务状态为进行中
    refresh_job.update!(
      status: 'running',
      started_at: Time.current
    )
    
    account_ids = refresh_job.account_ids
    successful_count = 0
    failed_count = 0
    
    # 逐个刷新账号配额
    account_ids.each_with_index do |account_id, index|
      begin
        account = AwsAccount.find(account_id)
        next unless account.active?
        
        # 调用配额刷新服务
        service = AwsService.new(account)
        quota_data = service.fetch_quotas
        
        if quota_data.present?
          # 更新配额数据
          update_account_quotas(account, quota_data)
          successful_count += 1
          
          # 记录审计日志
          AuditLog.log_action('bulk_refresh_quota',
            admin: nil,
            target: account,
            ip_address: 'system',
            user_agent: 'BulkRefreshJob',
            successful: true,
            metadata: { details: "批量刷新配额成功" }
          )
        else
          failed_count += 1
          Rails.logger.warn "Bulk refresh failed for account #{account.account_name}: No quota data returned"
        end
        
        # 更新进度
        progress = ((index + 1).to_f / account_ids.count * 100).round(1)
        refresh_job.update!(
          progress: progress,
          successful_accounts: successful_count,
          failed_accounts: failed_count
        )
        
        # 避免API限制，添加延迟
        sleep(0.5)
        
      rescue => e
        failed_count += 1
        Rails.logger.error "Bulk refresh error for account #{account_id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        # 记录失败日志
        if account
          AuditLog.log_action('bulk_refresh_quota_failed',
            admin: nil,
            target: account,
            ip_address: 'system',
            user_agent: 'BulkRefreshJob',
            successful: false,
            error_message: e.message,
            metadata: { details: "批量刷新配额失败: #{e.message}" }
          )
        end
      end
    end
    
    # 更新最终状态
    final_status = failed_count == 0 ? 'completed' : 'partially_completed'
    refresh_job.update!(
      status: final_status,
      completed_at: Time.current,
      successful_accounts: successful_count,
      failed_accounts: failed_count,
      progress: 100.0
    )
    
    # 发送完成通知（如果需要）
    notify_completion(refresh_job) if successful_count > 0
    
  rescue => e
    # 任务执行失败
    refresh_job.update!(
      status: 'failed',
      completed_at: Time.current,
      error_message: e.message
    )
    
    Rails.logger.error "Bulk refresh job failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    
    raise e
  end
  
  private
  
  def update_account_quotas(account, quota_data)
    quota_data.each do |service_code, data|
      quota = account.quotas.find_or_initialize_by(service_code: service_code)
      
      old_remaining = quota.quota_remaining || 0
      
      quota.assign_attributes(
        quota_limit: data[:quota_limit] || 0,
        quota_used: data[:quota_used] || 0,
        quota_remaining: data[:quota_remaining] || 0,
        last_updated_at: Time.current
      )
      
      if quota.save
        # 记录配额变化历史
        if quota.quota_remaining != old_remaining
          QuotaHistory.create!(
            aws_account: account,
            quota: quota,
            service_code: service_code,
            quota_used: data[:quota_used] || 0,
            quota_remaining: quota.quota_remaining,
            quota_limit: quota.quota_limit,
            change_amount: quota.quota_remaining - old_remaining,
            change_type: quota.quota_remaining > old_remaining ? 'increase' : 'decrease'
          )
        end
      end
    end
  end
  
  def notify_completion(refresh_job)
    # 这里可以添加通知逻辑，比如发送邮件或系统通知
    # 暂时只记录日志
    Rails.logger.info "Bulk refresh completed: #{refresh_job.successful_accounts} successful, #{refresh_job.failed_accounts} failed"
  end
end