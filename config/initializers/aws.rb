# frozen_string_literal: true

# AWS SDK Configuration for Claude Shop

# Configure AWS SDK
Aws.config.update(
  # Default region
  region: ENV.fetch('AWS_DEFAULT_REGION', 'us-east-1'),
  
  # Retry configuration
  retry_limit: 3,
  retry_delay: 1,
  
  # HTTP configuration
  http_read_timeout: 30,
  http_open_timeout: 15,
  
  # Logging
  logger: Rails.logger,
  log_level: Rails.env.development? ? :debug : :info,
  
  # SSL configuration
  ssl_verify_peer: true,
  
  # User agent
  user_agent_suffix: "claude-shop/#{Rails.application.class.module_parent_name.downcase}"
)

# Configure specific service clients if needed
if Rails.env.production?
  # Production-specific configurations
  Aws.config.update(
    log_level: :warn,
    http_read_timeout: 60,
    retry_limit: 5
  )
end

# Validate AWS gem availability
begin
  require 'aws-sdk-bedrock'
  Rails.logger.info "AWS Bedrock SDK loaded successfully"
rescue LoadError => e
  Rails.logger.error "Failed to load AWS Bedrock SDK: #{e.message}"
end

# Log AWS configuration
Rails.logger.info "AWS SDK configured with region: #{Aws.config[:region]}"