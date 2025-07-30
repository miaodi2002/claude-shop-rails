# frozen_string_literal: true

class AwsService
  # AWS SDK Configuration
  BEDROCK_REGIONS = %w[
    us-east-1 us-west-2 eu-west-1 ap-southeast-1 ap-northeast-1
  ].freeze
  
  DEFAULT_REGION = 'us-east-1'
  
  class << self
    # Test AWS credentials
    def test_credentials(access_key, secret_key, region = DEFAULT_REGION)
      client = create_bedrock_client(access_key, secret_key, region)
      
      # Test connection by making a simple API call
      response = client.list_foundation_models
      
      {
        success: true,
        region: region,
        models_count: response.model_summaries.count,
        available_models: extract_claude_models(response.model_summaries)
      }
    rescue Aws::Errors::ServiceError => e
      {
        success: false,
        error: e.message,
        error_code: e.code,
        region: region
      }
    rescue => e
      {
        success: false,
        error: e.message,
        error_code: 'UNKNOWN_ERROR',
        region: region
      }
    end
    
    # Get quota information for Claude models using Service Quotas API
    def get_quota_info(access_key, secret_key, region = DEFAULT_REGION)
      service_quotas_client = create_service_quotas_client(access_key, secret_key, region)
      
      quotas = []
      
      # First, discover the actual quota codes
      quota_codes = find_bedrock_quota_codes(service_quotas_client)
      
      # Check quotas for each model and quota type
      AwsQuotaService::CLAUDE_MODELS.each do |model_name, model_config|
        # Get the quota types for this specific model
        model_quota_types = AwsQuotaService.quota_types_for_model(model_name)
        
        model_quota_types.each do |quota_key|
          quota_description = AwsQuotaService.quota_description(quota_key)
          
          # Try to find the specific quota code
          quota_code_key = AwsQuotaService.quota_key(model_name, quota_key)
          quota_code = quota_codes[quota_code_key]
          
          begin
            if quota_code
              current_value, default_value, is_adjustable = get_quota_value(service_quotas_client, 'bedrock', quota_code)
            else
              current_value, default_value, is_adjustable = nil, nil, nil
            end
            
            # Determine display values
            current_display = current_value || 'N/A'
            default_display = default_value || 'N/A'
            
            # Evaluate quota level using simplified logic (High if >= default, Low otherwise)
            quota_level = AwsQuotaService.evaluate_quota_level(quota_key, current_value, default_value)
            
            quotas << {
              model_name: model_name,
              model_id: model_config[:model_id],
              quota_type: quota_key,
              quota_description: quota_description,
              quota_limit: current_value || 0,  # Only store the actual quota limit
              default_value: default_value || 0,
              is_adjustable: is_adjustable || false,
              quota_level: quota_level,
              aws_quota_code: quota_code,
              last_updated: Time.current
            }
          rescue => e
            Rails.logger.error "Failed to get quota for #{model_name} #{quota_key}: #{e.message}"
            
            quotas << {
              model_name: model_name,
              model_id: model_config[:model_id],
              quota_type: quota_key,
              quota_description: quota_description,
              quota_limit: 0,  # Error case, set to 0
              default_value: 0,
              is_adjustable: false,
              quota_level: 'N/A',
              aws_quota_code: quota_code,
              last_updated: Time.current,
              error: e.message
            }
          end
        end
      end
      
      {
        success: true,
        region: region,
        quotas: quotas,
        total_models: quotas.count
      }
    rescue Aws::Errors::ServiceError => e
      {
        success: false,
        error: e.message,
        error_code: e.code,
        region: region
      }
    rescue => e
      {
        success: false,
        error: e.message,
        error_code: 'UNKNOWN_ERROR',
        region: region
      }
    end
    
    # Refresh quota for a specific AWS account
    def refresh_account_quotas(aws_account)
      # 使用新的 AwsQuotaService 来刷新配额
      begin
        results = AwsQuotaService.refresh_all_quotas(aws_account)
        
        # Update account connection status
        aws_account.update!(
          connection_status: :connected,
          last_connection_test_at: Time.current,
          connection_error_message: nil
        )
        
        {
          success: true,
          quotas: aws_account.account_quotas.includes(:quota_definition).map do |aq|
            {
              model_name: aq.quota_definition.claude_model_name,
              quota_type: aq.quota_definition.quota_type,
              current_quota: aq.current_quota,
              quota_level: aq.quota_level,
              is_adjustable: aq.is_adjustable
            }
          end,
          successful: results[:success],
          failed: results[:failed],
          errors: results[:errors]
        }
      rescue => e
        # Update account with error status
        aws_account.update!(
          connection_status: :error,
          connection_error_message: e.message
        )
        
        # Mark all quotas as failed
        aws_account.account_quotas.update_all(sync_status: 'failed', sync_error: e.message)
        
        {
          success: false,
          error: e.message,
          error_code: 'REFRESH_ERROR'
        }
      end
    end
    
    # Batch refresh multiple accounts
    def refresh_batch_quotas(aws_accounts, job = nil)
      results = {
        total: aws_accounts.count,
        successful: 0,
        failed: 0,
        errors: []
      }
      
      aws_accounts.find_each.with_index do |account, index|
        begin
          result = refresh_account_quotas(account)
          
          if result[:success]
            results[:successful] += 1
          else
            results[:failed] += 1
            results[:errors] << {
              account_id: account.account_id,
              account_name: account.name,
              error: result[:error]
            }
          end
          
          # Update job progress if provided
          if job
            progress = ((index + 1).to_f / aws_accounts.count * 100).round(2)
            job.update_progress(index + 1)
          end
          
        rescue => e
          results[:failed] += 1
          results[:errors] << {
            account_id: account.account_id,
            account_name: account.name,
            error: e.message
          }
          
          Rails.logger.error "Failed to refresh account #{account.account_id}: #{e.message}"
        end
      end
      
      results
    end
    
    # Get available regions for AWS Bedrock
    def available_regions
      BEDROCK_REGIONS.map do |region|
        {
          code: region,
          name: region_name(region),
          default: region == DEFAULT_REGION
        }
      end
    end
    
    # Test connection to specific region
    def test_region_connection(access_key, secret_key, region)
      start_time = Time.current
      
      result = test_credentials(access_key, secret_key, region)
      
      end_time = Time.current
      response_time = ((end_time - start_time) * 1000).round(2) # milliseconds
      
      result.merge(
        response_time_ms: response_time,
        tested_at: end_time
      )
    end
    
    private
    
    # Get mock quota information (temporary solution)
    def get_mock_quota_info(region)
      quotas = []
      
      # Generate mock data for each model and quota type
      AwsQuotaService::CLAUDE_MODELS.each do |model_name, model_config|
        model_quota_types = AwsQuotaService.quota_types_for_model(model_name)
        
        model_quota_types.each do |quota_key|
          quota_description = AwsQuotaService.quota_description(quota_key)
          
          # Generate realistic mock values based on quota type
          case quota_key
          when 'requests_per_minute'
            current_value = rand(1000..5000)
            default_value = 1000
          when 'tokens_per_minute'
            current_value = rand(50000..200000)
            default_value = 50000
          when 'tokens_per_day'
            current_value = rand(1000000..5000000)
            default_value = 1000000
          else
            current_value = rand(1000..10000)
            default_value = 1000
          end
          
          # Evaluate quota level
          quota_level = AwsQuotaService.evaluate_quota_level(quota_key, current_value)
          
          quotas << {
            model_name: model_name,
            model_id: model_config[:model_id],
            quota_type: quota_key,
            quota_description: quota_description,
            quota_limit: current_value,
            quota_used: rand(0..current_value/2), # Random usage up to 50%
            quota_remaining: current_value - rand(0..current_value/2),
            default_value: default_value,
            is_adjustable: true,
            quota_level: quota_level,
            aws_quota_code: "mock-#{model_name}-#{quota_key}",
            last_updated: Time.current
          }
        end
      end
      
      {
        success: true,
        region: region,
        quotas: quotas,
        total_models: quotas.count
      }
    end
    
    # Create AWS Bedrock client
    def create_bedrock_client(access_key, secret_key, region)
      Aws::Bedrock::Client.new(
        access_key_id: access_key,
        secret_access_key: secret_key,
        region: region,
        retry_limit: 3
      )
    end
    
    
    # Create AWS Service Quotas client
    def create_service_quotas_client(access_key, secret_key, region)
      Rails.logger.info "Creating ServiceQuotas client for region: #{region}"
      Aws::ServiceQuotas::Client.new(
        access_key_id: access_key,
        secret_access_key: secret_key,
        region: region
      )
    end
    
    
    # Extract Claude models from AWS response
    def extract_claude_models(model_summaries)
      claude_models = []
      
      model_summaries.each do |model|
        next unless model.model_id.include?('claude')
        
        claude_models << {
          model_id: model.model_id,
          model_name: format_model_name(model.model_id),
          provider_name: model.provider_name,
          input_modalities: model.input_modalities,
          output_modalities: model.output_modalities
        }
      end
      
      claude_models
    end
    
    # Format model ID to readable name
    def format_model_name(model_id)
      # Convert model IDs like "anthropic.claude-3-sonnet-20240229-v1:0" 
      # to "Claude-3-Sonnet"
      name_parts = model_id.split('.')
      return model_id unless name_parts.length > 1
      
      model_part = name_parts[1]
      model_part = model_part.split('-')[0..2].join('-') if model_part.include?('-')
      
      model_part.titleize
    end
    
    # Get quota value for a specific service and quota code
    def get_quota_value(service_quotas_client, service_code, quota_code)
      begin
        # Try to get the applied quota value first
        response = service_quotas_client.get_service_quota(
          service_code: service_code,
          quota_code: quota_code
        )
        
        quota = response.quota
        current_value = quota.value
        is_adjustable = quota.adjustable
        
        # Get default value
        default_response = service_quotas_client.get_aws_default_service_quota(
          service_code: service_code,
          quota_code: quota_code
        )
        default_value = default_response.quota.value
        
        [current_value, default_value, is_adjustable]
        
      rescue => e
        if defined?(Aws::ServiceQuotas::Errors::NoSuchResourceException) && e.is_a?(Aws::ServiceQuotas::Errors::NoSuchResourceException)
          Rails.logger.debug "Quota #{quota_code} not found"
        else
          Rails.logger.error "Error getting quota #{quota_code}: #{e.message}"
        end
        [nil, nil, nil]
      rescue Aws::Errors::ServiceError => e
        Rails.logger.error "Error getting quota #{quota_code}: #{e.message}"
        [nil, nil, nil]
      rescue => e
        Rails.logger.error "Unexpected error getting quota #{quota_code}: #{e.message}"
        [nil, nil, nil]
      end
    end
    
    # Find the actual quota codes for Bedrock Claude models
    def find_bedrock_quota_codes(service_quotas_client)
      Rails.logger.info "Discovering Bedrock quota codes..."
      
      begin
        quota_mapping = {}
        
        # List all quotas for bedrock service
        paginator = service_quotas_client.list_service_quotas(service_code: 'bedrock')
        
        paginator.each_page do |page|
          page.quotas.each do |quota|
            quota_name = quota.quota_name
            quota_code = quota.quota_code
            
            # Match quotas based on specific model patterns
            AwsQuotaService::CLAUDE_MODELS.each do |model_name, model_config|
              quota_pattern = model_config[:quota_pattern]
              
              # Check for exact pattern match in quota name
              if quota_name.include?(quota_pattern)
                # Identify quota type (note case sensitivity)
                if quota_name.include?('Cross-Region model inference requests per minute') || 
                   quota_name.include?('Cross-region model inference requests per minute')
                  key = AwsQuotaService.quota_key(model_name, 'requests_per_minute')
                  quota_mapping[key] = quota_code
                elsif quota_name.include?('Cross-Region model inference tokens per minute') ||
                      quota_name.include?('Cross-region model inference tokens per minute')
                  key = AwsQuotaService.quota_key(model_name, 'tokens_per_minute')
                  quota_mapping[key] = quota_code
                elsif quota_name.include?('Model invocation max tokens per day') && 
                      quota_name.include?('doubled for cross-region calls')
                  key = AwsQuotaService.quota_key(model_name, 'tokens_per_day')
                  quota_mapping[key] = quota_code
                end
              end
            end
          end
        end
        
        Rails.logger.debug "Found #{quota_mapping.size} quota mappings"
        quota_mapping
        
      rescue => e
        Rails.logger.error "Error discovering quota codes: #{e.message}"
        {}
      end
    end
    
    # Parse quota value handling 'N/A' and 'Error' cases
    def parse_quota_value(value)
      return nil if value.nil? || value == 'N/A' || value == 'Error'
      
      case value
      when String
        value.to_f
      when Numeric
        value.to_f
      else
        nil
      end
    end
    
    # Get human-readable region name
    def region_name(region_code)
      region_names = {
        'us-east-1' => 'US East (N. Virginia)',
        'us-west-2' => 'US West (Oregon)',
        'eu-west-1' => 'Europe (Ireland)',
        'ap-southeast-1' => 'Asia Pacific (Singapore)',
        'ap-northeast-1' => 'Asia Pacific (Tokyo)'
      }
      
      region_names[region_code] || region_code.upcase
    end
  end
end