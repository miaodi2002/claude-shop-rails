# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    def index
      @stats = {
        total_accounts: AwsAccount.count,
        active_accounts: AwsAccount.active.count,
        total_quota: 0, # Quota.sum(:quota_remaining),
        recent_logins: [] # AuditLog.where(action: 'login').recent.limit(5)
      }
      
      # 获取配额使用趋势数据
      @quota_trend = {} # Temporarily disabled
      
      # 获取账号状态分布
      @account_status_distribution = AwsAccount.group(:status).count
      
      # 获取最近的刷新任务
      @recent_refresh_jobs = [] # RefreshJob.recent.limit(5) # Temporarily disabled
      
      # 系统健康检查
      @system_health = check_system_health
    end
    
    private
    
    def check_system_health
      {
        database: database_healthy?,
        redis: redis_healthy?,
        aws_connection: aws_connection_healthy?,
        last_refresh: last_refresh_time
      }
    end
    
    def database_healthy?
      ActiveRecord::Base.connection.active?
    rescue
      false
    end
    
    def redis_healthy?
      Redis.current.ping == "PONG"
    rescue
      false
    end
    
    def aws_connection_healthy?
      # 简单检查是否有成功连接的账号
      AwsAccount.where(connection_status: :connected).exists?
    end
    
    def last_refresh_time
      RefreshJob.completed.order(completed_at: :desc).first&.completed_at
    end
  end
end