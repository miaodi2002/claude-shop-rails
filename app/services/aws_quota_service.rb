# frozen_string_literal: true

class AwsQuotaService
  class << self
    # Claude 模型配置
    CLAUDE_MODELS = {
      'Claude 3.5 Sonnet V1' => {
        quota_pattern: 'Claude 3.5 Sonnet',
        model_id: 'anthropic.claude-3-5-sonnet',
        version: 'V1'
      },
      'Claude 3.5 Sonnet V2' => {
        quota_pattern: 'Claude 3.5 Sonnet V2',
        model_id: 'anthropic.claude-3-5-sonnet-v2',
        version: 'V2'
      },
      'Claude 3.7 Sonnet V1' => {
        quota_pattern: 'Claude 3.7 Sonnet V1',
        model_id: 'anthropic.claude-3-7-sonnet',
        version: 'V1'
      },
      'Claude 4 Sonnet V1' => {
        quota_pattern: 'Claude Sonnet 4 V1',
        model_id: 'anthropic.claude-4-sonnet',
        version: 'V1'
      }
    }.freeze

    # 预定义的配额定义数据
    QUOTA_DEFINITIONS = [
      # Claude 3.5 Sonnet V1
      { 
        quota_code: 'L-254CACF4', 
        claude_model_name: 'Claude 3.5 Sonnet V1', 
        quota_type: 'requests_per_minute', 
        quota_name: 'On-demand model inference requests per minute for Anthropic Claude 3.5 Sonnet', 
        call_type: 'On-demand',
        default_value: 50 
      },
      { 
        quota_code: 'L-A50569E5', 
        claude_model_name: 'Claude 3.5 Sonnet V1', 
        quota_type: 'tokens_per_minute', 
        quota_name: 'On-demand model inference tokens per minute for Anthropic Claude 3.5 Sonnet', 
        call_type: 'On-demand',
        default_value: 400000
      },
      
      # Claude 3.5 Sonnet V2
      { 
        quota_code: 'L-79E773B3', 
        claude_model_name: 'Claude 3.5 Sonnet V2', 
        quota_type: 'requests_per_minute', 
        quota_name: 'On-demand model inference requests per minute for Anthropic Claude 3.5 Sonnet V2', 
        call_type: 'On-demand',
        default_value: 50
      },
      { 
        quota_code: 'L-AD41C330', 
        claude_model_name: 'Claude 3.5 Sonnet V2', 
        quota_type: 'tokens_per_minute', 
        quota_name: 'On-demand model inference tokens per minute for Anthropic Claude 3.5 Sonnet V2', 
        call_type: 'On-demand',
        default_value: 400000
      },
      
      # Claude 3.7 Sonnet V1
      { 
        quota_code: 'L-3D8CC480', 
        claude_model_name: 'Claude 3.7 Sonnet V1', 
        quota_type: 'requests_per_minute', 
        quota_name: 'Cross-region model inference requests per minute for Anthropic Claude 3.7 Sonnet V1', 
        call_type: 'Cross-region',
        default_value: 250
      },
      { 
        quota_code: 'L-6E888CC2', 
        claude_model_name: 'Claude 3.7 Sonnet V1', 
        quota_type: 'tokens_per_minute', 
        quota_name: 'Cross-region model inference tokens per minute for Anthropic Claude 3.7 Sonnet V1', 
        call_type: 'Cross-region',
        default_value: 1000000
      },
      { 
        quota_code: 'L-9EB71894', 
        claude_model_name: 'Claude 3.7 Sonnet V1', 
        quota_type: 'tokens_per_day', 
        quota_name: 'Model invocation max tokens per day for Anthropic Claude 3.7 Sonnet V1 (doubled for cross-region calls)', 
        call_type: 'Cross-region',
        default_value: 720000000
      },
      
      # Claude 4 Sonnet V1
      { 
        quota_code: 'L-559DCC33', 
        claude_model_name: 'Claude 4 Sonnet V1', 
        quota_type: 'requests_per_minute', 
        quota_name: 'Cross-region model inference requests per minute for Anthropic Claude Sonnet 4 V1', 
        call_type: 'Cross-region',
        default_value: 200
      },
      { 
        quota_code: 'L-59759B4A', 
        claude_model_name: 'Claude 4 Sonnet V1', 
        quota_type: 'tokens_per_minute', 
        quota_name: 'Cross-region model inference tokens per minute for Anthropic Claude Sonnet 4 V1', 
        call_type: 'Cross-region',
        default_value: 200000
      },
      { 
        quota_code: 'L-22F701C5', 
        claude_model_name: 'Claude 4 Sonnet V1', 
        quota_type: 'tokens_per_day', 
        quota_name: 'Model invocation max tokens per day for Anthropic Claude Sonnet 4 V1 (doubled for cross-region calls)', 
        call_type: 'Cross-region',
        default_value: 144000000
      }
    ].freeze
    
    # 初始化配额定义
    def sync_quota_definitions!
      Rails.logger.info "Syncing quota definitions..."
      
      success_count = 0
      QUOTA_DEFINITIONS.each do |definition|
        qd = QuotaDefinition.find_or_initialize_by(quota_code: definition[:quota_code])
        
        if qd.update(definition)
          success_count += 1
          Rails.logger.info "Synced quota definition: #{definition[:claude_model_name]} - #{definition[:quota_type]}"
        else
          Rails.logger.error "Failed to sync quota definition: #{qd.errors.full_messages.join(', ')}"
        end
      end
      
      Rails.logger.info "Successfully synced #{success_count}/#{QUOTA_DEFINITIONS.count} quota definitions"
      success_count
    end
    
    # 获取单个配额信息
    def fetch_single_quota(aws_account, quota_code)
      client = create_service_quotas_client(aws_account)
      
      begin
        response = client.get_service_quota(
          service_code: 'bedrock',
          quota_code: quota_code
        )
        
        {
          success: true,
          value: response.quota.value,
          adjustable: response.quota.adjustable,
          raw_data: response.to_h
        }
      rescue Aws::ServiceQuotas::Errors::NoSuchResourceException => e
        # 配额不存在，尝试获取默认值
        begin
          default_response = client.get_aws_default_service_quota(
            service_code: 'bedrock',
            quota_code: quota_code
          )
          
          {
            success: true,
            value: default_response.quota.value,
            adjustable: false,
            raw_data: default_response.to_h
          }
        rescue => e
          Rails.logger.error "Failed to get default quota for #{quota_code}: #{e.message}"
          { success: false, error: "Quota not found: #{e.message}" }
        end
      rescue Aws::Errors::ServiceError => e
        Rails.logger.error "AWS Service Error for quota #{quota_code}: #{e.message}"
        { success: false, error: "AWS Service Error: #{e.message}" }
      rescue => e
        Rails.logger.error "Unexpected error fetching quota #{quota_code}: #{e.message}"
        { success: false, error: e.message }
      end
    end
    
    # 刷新账号的所有配额
    def refresh_all_quotas(aws_account)
      Rails.logger.info "Refreshing all quotas for account: #{aws_account.name}"
      
      results = { success: 0, failed: 0, errors: [] }
      
      # 确保账号有所有活跃的配额记录
      ensure_account_quotas(aws_account)
      
      # 刷新每个配额
      aws_account.account_quotas.includes(:quota_definition).find_each do |account_quota|
        begin
          if account_quota.refresh!
            results[:success] += 1
          else
            results[:failed] += 1
            results[:errors] << "#{account_quota.display_name}: Failed to refresh"
          end
        rescue => e
          results[:failed] += 1  
          results[:errors] << "#{account_quota.display_name}: #{e.message}"
          Rails.logger.error "Error refreshing quota #{account_quota.id}: #{e.message}"
        end
      end
      
      # 更新账号的最后配额更新时间
      aws_account.update(last_quota_update_at: Time.current)
      
      Rails.logger.info "Quota refresh completed: #{results[:success]} success, #{results[:failed]} failed"
      results
    end
    
    private
    
    # 创建 AWS Service Quotas 客户端
    def create_service_quotas_client(aws_account)
      Aws::ServiceQuotas::Client.new(
        access_key_id: aws_account.access_key,
        secret_access_key: aws_account.secret_key,
        region: aws_account.region || 'us-east-1'
      )
    end
    
    # 确保账号有所有配额定义的记录
    def ensure_account_quotas(aws_account)
      QuotaDefinition.active.find_each do |definition|
        aws_account.account_quotas.find_or_create_by(quota_definition: definition) do |aq|
          Rails.logger.info "Creating account quota for: #{definition.display_name}"
        end
      end
    end

    # 获取模型的配额类型
    def quota_types_for_model(model_name)
      # 根据模型名称返回对应的配额类型
      case model_name
      when /Claude 3.5 Sonnet/, /Claude 3.7 Sonnet/, /Claude 4 Sonnet/
        ['requests_per_minute', 'tokens_per_minute', 'tokens_per_day'].select do |type|
          # 检查这个模型是否有这种类型的配额定义
          QUOTA_DEFINITIONS.any? { |quota_def| quota_def[:claude_model_name].start_with?(model_name.split(' V')[0]) && quota_def[:quota_type] == type }
        end
      else
        []
      end
    end

    # 获取配额描述
    def quota_description(quota_key)
      case quota_key
      when 'requests_per_minute'
        'Requests per minute'
      when 'tokens_per_minute'
        'Tokens per minute'
      when 'tokens_per_day'
        'Tokens per day'
      else
        quota_key.humanize
      end
    end

    # 生成配额键
    def quota_key(model_name, quota_type)
      "#{model_name}-#{quota_type}"
    end

    # 评估配额等级
    def evaluate_quota_level(quota_type, current_value, default_value = nil)
      return 'unknown' if current_value.nil? || default_value.nil?
      
      # 统一的三级判断逻辑：基于default_value进行比较
      if current_value < default_value
        'low'
      elsif current_value == default_value
        'medium'
      else
        'high'
      end
    end
  end
end
