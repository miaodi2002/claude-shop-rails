module Aws
  class QuotaFetcher
    include ActiveModel::Model
    include ActiveModel::Attributes
    
    attr_accessor :aws_account
    
    # Claude 模型配置
    CLAUDE_MODELS = {
      'claude-3-5-sonnet-20241022' => {
        service_code: 'bedrock',
        quota_code: 'L-xxxxx',  # 实际的配额代码
        display_name: 'Claude 3.5 Sonnet'
      },
      'claude-3-haiku-20240307' => {
        service_code: 'bedrock',
        quota_code: 'L-yyyyy',
        display_name: 'Claude 3 Haiku'
      },
      'claude-3-opus-20240229' => {
        service_code: 'bedrock',
        quota_code: 'L-zzzzz',
        display_name: 'Claude 3 Opus'
      }
    }.freeze
    
    def initialize(aws_account)
      @aws_account = aws_account
      @client = build_client
    end
    
    def fetch_all_quotas
      results = {}
      
      CLAUDE_MODELS.each do |model_name, config|
        begin
          quota_data = fetch_quota_for_model(model_name, config)
          results[model_name] = quota_data
          
          # 更新或创建配额记录
          update_quota_record(model_name, quota_data)
          
        rescue => e
          Rails.logger.error "Failed to fetch quota for #{model_name}: #{e.message}"
          results[model_name] = { error: e.message }
        end
      end
      
      # 更新账号最后刷新时间
      aws_account.update!(last_quota_update_at: Time.current)
      
      results
    end
    
    def fetch_quota_for_model(model_name, config = nil)
      config ||= CLAUDE_MODELS[model_name]
      raise ArgumentError, "Unknown model: #{model_name}" unless config
      
      # 使用 AWS Service Quotas API 获取配额信息
      response = @client.get_service_quota(
        service_code: config[:service_code],
        quota_code: config[:quota_code]
      )
      
      quota_info = response.quota
      
      # 获取使用量信息（这可能需要调用其他API）
      usage_info = fetch_usage_for_model(model_name, config)
      
      {
        limit: quota_info.value.to_i,
        used: usage_info[:used] || 0,
        remaining: [quota_info.value.to_i - (usage_info[:used] || 0), 0].max,
        unit: quota_info.unit,
        last_updated: Time.current,
        raw_data: {
          quota_response: quota_info.to_h,
          usage_response: usage_info
        }
      }
    end
    
    def test_connection
      begin
        # 简单的API调用来测试连接
        @client.list_services(max_results: 1)
        { success: true, message: '连接成功' }
      rescue ::Aws::Errors::ServiceError => e
        { success: false, error: "AWS API 错误: #{e.message}" }
      rescue => e
        { success: false, error: "连接失败: #{e.message}" }
      end
    end
    
    private
    
    def build_client
      ::Aws::ServiceQuotas::Client.new(
        access_key_id: aws_account.access_key,
        secret_access_key: aws_account.secret_key,
        region: 'us-east-1'  # Service Quotas 主要在 us-east-1
      )
    end
    
    def fetch_usage_for_model(model_name, config)
      # 这里需要根据实际情况调用相应的API来获取使用量
      # 可能需要调用 CloudWatch 或其他监控服务
      
      begin
        # 示例：使用 CloudWatch 获取使用量
        cloudwatch_client = ::Aws::CloudWatch::Client.new(
          access_key_id: aws_account.access_key,
          secret_access_key: aws_account.secret_key,
          region: 'us-east-1'
        )
        
        # 获取过去24小时的使用量
        end_time = Time.current
        start_time = end_time - 24.hours
        
        response = cloudwatch_client.get_metric_statistics(
          namespace: 'AWS/Bedrock',
          metric_name: 'Invocations',
          dimensions: [
            {
              name: 'ModelId',
              value: model_name
            }
          ],
          start_time: start_time,
          end_time: end_time,
          period: 3600,  # 1小时
          statistics: ['Sum']
        )
        
        total_used = response.datapoints.sum { |dp| dp.sum.to_i }
        
        {
          used: total_used,
          period: '24h',
          raw_data: response.to_h
        }
        
      rescue => e
        Rails.logger.warn "Failed to fetch usage data for #{model_name}: #{e.message}"
        {
          used: 0,
          error: e.message
        }
      end
    end
    
    def update_quota_record(model_name, quota_data)
      quota = aws_account.quotas.find_or_initialize_by(model_name: model_name)
      
      if quota_data[:error]
        quota.update!(
          update_status: 'failed',
          update_error_message: quota_data[:error]
        )
      else
        quota.update_from_aws!(quota_data)
      end
    end
    
    # 类方法
    def self.available_models
      CLAUDE_MODELS.keys
    end
    
    def self.model_display_name(model_name)
      CLAUDE_MODELS.dig(model_name, :display_name) || model_name
    end
    
    def self.refresh_account_quotas(account_id)
      account = AwsAccount.find(account_id)
      fetcher = new(account)
      fetcher.fetch_all_quotas
    end
    
    def self.batch_refresh(account_ids = nil)
      scope = account_ids ? AwsAccount.where(id: account_ids) : AwsAccount.active.connected
      
      results = {}
      
      scope.find_each do |account|
        begin
          fetcher = new(account)
          results[account.id] = fetcher.fetch_all_quotas
        rescue => e
          Rails.logger.error "Batch refresh failed for account #{account.id}: #{e.message}"
          results[account.id] = { error: e.message }
        end
      end
      
      results
    end
  end
end