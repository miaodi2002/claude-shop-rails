# frozen_string_literal: true

class AwsAccountInfoService
  class << self
    # 获取AWS账号信息
    def fetch_account_info(access_key, secret_key, region = 'us-east-1')
      client = create_sts_client(access_key, secret_key, region)
      
      begin
        # 使用STS get_caller_identity获取账号信息
        response = client.get_caller_identity
        
        {
          success: true,
          account_id: response.account,
          user_id: response.user_id,
          arn: response.arn,
          raw_data: response.to_h
        }
      rescue Aws::STS::Errors::InvalidUserType => e
        Rails.logger.error "Invalid AWS user type: #{e.message}"
        { success: false, error: "无效的AWS用户类型: #{e.message}", error_code: 'invalid_user_type' }
      rescue Aws::STS::Errors::AccessDenied => e
        Rails.logger.error "AWS access denied: #{e.message}"
        { success: false, error: "AWS访问被拒绝，请检查密钥权限: #{e.message}", error_code: 'access_denied' }
      rescue Aws::Errors::ServiceError => e
        Rails.logger.error "AWS Service Error: #{e.message}"
        { success: false, error: "AWS服务错误: #{e.message}", error_code: 'service_error' }
      rescue => e
        Rails.logger.error "Unexpected error fetching account info: #{e.message}"
        { success: false, error: "获取账号信息时发生错误: #{e.message}", error_code: 'unknown_error' }
      end
    end
    
    # 验证AWS凭证并获取账号信息
    def validate_and_fetch_info(access_key, secret_key, region = 'us-east-1')
      return { success: false, error: "Access Key不能为空", error_code: 'missing_access_key' } if access_key.blank?
      return { success: false, error: "Secret Key不能为空", error_code: 'missing_secret_key' } if secret_key.blank?
      
      # 验证Access Key格式
      unless access_key.match?(/\AAKIA[0-9A-Z]{16,}\z/)
        return { success: false, error: "无效的Access Key格式", error_code: 'invalid_access_key_format' }
      end
      
      # 验证Secret Key长度
      unless secret_key.length >= 40
        return { success: false, error: "Secret Key长度不足，至少需要40个字符", error_code: 'invalid_secret_key_length' }
      end
      
      # 获取账号信息
      fetch_account_info(access_key, secret_key, region)
    end
    
    # 为新的AWS账号获取并设置账号ID
    def fetch_and_set_account_id(aws_account)
      return { success: false, error: "AWS账号对象不能为空" } unless aws_account
      return { success: false, error: "Access Key未设置" } unless aws_account.access_key.present?
      return { success: false, error: "Secret Key未设置" } unless aws_account.secret_key.present?
      
      result = validate_and_fetch_info(
        aws_account.access_key,
        aws_account.secret_key, 
        aws_account.region || 'us-east-1'
      )
      
      if result[:success]
        # 设置账号ID
        aws_account.account_id = result[:account_id]
        
        # 记录获取的其他信息到日志
        Rails.logger.info "Successfully fetched account info for #{aws_account.name}: Account ID #{result[:account_id]}, ARN #{result[:arn]}"
        
        {
          success: true,
          account_id: result[:account_id],
          account_info: result
        }
      else
        Rails.logger.error "Failed to fetch account info for #{aws_account.name}: #{result[:error]}"
        result
      end
    end
    
    private
    
    # 创建AWS STS客户端
    def create_sts_client(access_key, secret_key, region)
      require 'aws-sdk-sts'
      
      Aws::STS::Client.new(
        access_key_id: access_key,
        secret_access_key: secret_key,
        region: region
      )
    end
  end
end