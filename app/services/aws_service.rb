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
    
    # Get quota information for Claude models
    def get_quota_info(access_key, secret_key, region = DEFAULT_REGION)
      client = create_bedrock_client(access_key, secret_key, region)
      
      # List available Claude models
      models_response = client.list_foundation_models
      claude_models = extract_claude_models(models_response.model_summaries)
      
      quotas = []
      
      claude_models.each do |model|
        begin
          # Get quota for each model (this is a mock implementation)
          # In real AWS Bedrock, quota information might be retrieved differently
          quota_info = get_model_quota(client, model[:model_id])
          
          quotas << {
            model_name: model[:model_name],
            model_id: model[:model_id],
            quota_limit: quota_info[:limit],
            quota_used: quota_info[:used],
            quota_remaining: quota_info[:limit] - quota_info[:used],
            last_updated: Time.current
          }
        rescue => e
          Rails.logger.error "Failed to get quota for #{model[:model_name]}: #{e.message}"
          
          # Add default quota if API call fails
          quotas << {
            model_name: model[:model_name],
            model_id: model[:model_id],
            quota_limit: 0,
            quota_used: 0,
            quota_remaining: 0,
            last_updated: Time.current,
            error: e.message
          }
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
      result = get_quota_info(
        aws_account.access_key,
        aws_account.secret_key,
        aws_account.region || DEFAULT_REGION
      )
      
      if result[:success]
        # Update quotas in database
        Quota.transaction do
          result[:quotas].each do |quota_data|
            quota = aws_account.quotas.find_or_initialize_by(
              model_name: quota_data[:model_name]
            )
            
            quota.update!(
              quota_limit: quota_data[:quota_limit],
              quota_used: quota_data[:quota_used],
              quota_remaining: quota_data[:quota_remaining],
              last_updated_at: Time.current,
              update_status: :success
            )
          end
        end
        
        # Update account connection status
        aws_account.update!(
          connection_status: :connected,
          last_connected_at: Time.current,
          connection_error: nil
        )
        
        result
      else
        # Update account with error status
        aws_account.update!(
          connection_status: :error,
          connection_error: result[:error]
        )
        
        # Mark all quotas as failed
        aws_account.quotas.update_all(update_status: :failed)
        
        result
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
    
    # Create AWS Bedrock client
    def create_bedrock_client(access_key, secret_key, region)
      Aws::Bedrock::Client.new(
        access_key_id: access_key,
        secret_access_key: secret_key,
        region: region,
        retry_limit: 3,
        retry_delay: 1
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
    
    # Get quota for specific model (mock implementation)
    def get_model_quota(client, model_id)
      # This is a mock implementation since AWS Bedrock doesn't have 
      # a direct quota API. In real implementation, this would use
      # AWS Service Quotas or CloudWatch metrics
      
      # Simulate different quota limits based on model
      base_limit = case model_id
                  when /claude-3-opus/
                    100_000
                  when /claude-3-sonnet/
                    500_000
                  when /claude-3-haiku/
                    1_000_000
                  else
                    10_000
                  end
      
      # Simulate random usage
      used = rand(0..(base_limit * 0.8).to_i)
      
      {
        limit: base_limit,
        used: used
      }
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