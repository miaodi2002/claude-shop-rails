# frozen_string_literal: true

class AwsCostExplorerService
  include ActiveModel::Model
  include ActiveModel::Attributes
  
  # Configuration
  MAX_RETRIES = 1
  TIMEOUT_SECONDS = 30
  GRANULARITY = 'DAILY'
  METRICS = ['UnblendedCost'].freeze
  GROUP_BY = [
    {
      type: 'DIMENSION',
      key: 'SERVICE'
    }
  ].freeze
  
  # Attributes
  attr_accessor :aws_account
  attribute :start_date, :date  
  attribute :end_date, :date
  attribute :retries, :integer, default: 0
  
  # Validations
  validates :aws_account, presence: true
  validates :start_date, :end_date, presence: true
  validate :date_range_valid?
  validate :aws_credentials_present?
  
  # Main sync method
  def sync_costs
    return failure("Invalid parameters") unless valid?
    
    begin
      Rails.logger.info "Starting cost sync for account #{aws_account.name} (#{start_date} to #{end_date})"
      
      # Get cost data from AWS
      cost_data = fetch_cost_data
      return failure("No cost data returned from AWS") if cost_data.blank?
      
      # Process and save data
      synced_count = process_cost_data(cost_data)
      
      success("Successfully synced #{synced_count} days of cost data")
    rescue Aws::CostExplorer::Errors::ServiceError => e
      handle_aws_error(e)
    rescue StandardError => e
      handle_generic_error(e)
    end
  end
  
  # Retry mechanism
  def sync_with_retry
    result = sync_costs
    
    if result[:success] || retries >= MAX_RETRIES
      return result
    end
    
    # Retry once on failure
    self.retries += 1
    Rails.logger.info "Retrying cost sync for account #{aws_account.name} (attempt #{retries + 1})"
    
    sleep(2) # Wait before retry
    sync_costs
  end
  
  # Get account credentials as AWS config
  def aws_config
    {
      access_key_id: aws_account.access_key,
      secret_access_key: aws_account.secret_key,
      region: aws_account.region || 'us-east-1'
    }
  end

  private
  
  def fetch_cost_data
    client = Aws::CostExplorer::Client.new(aws_config.merge(
      http_read_timeout: TIMEOUT_SECONDS,
      http_open_timeout: TIMEOUT_SECONDS,
      retry_limit: 0 # We handle retries manually
    ))
    
    response = client.get_cost_and_usage({
      time_period: {
        start: start_date.strftime('%Y-%m-%d'),
        end: (end_date + 1.day).strftime('%Y-%m-%d') # AWS uses exclusive end date
      },
      granularity: GRANULARITY,
      metrics: METRICS,
      group_by: GROUP_BY
    })
    
    response.results_by_time
  rescue Aws::CostExplorer::Errors::ServiceError => e
    Rails.logger.error "AWS CostExplorer API error: #{e.message}"
    raise e
  end
  
  def process_cost_data(results_by_time)
    synced_count = 0
    
    results_by_time.each do |result|
      date = Date.parse(result.time_period.start)
      total_cost = calculate_total_cost(result.groups)
      
      # Create or update daily cost record
      daily_cost = aws_account.daily_costs.find_or_initialize_by(date: date)
      daily_cost.cost_amount = total_cost
      daily_cost.currency = 'USD'
      
      if daily_cost.save
        synced_count += 1
        Rails.logger.debug "Saved cost for #{date}: $#{total_cost}"
      else
        Rails.logger.warn "Failed to save cost for #{date}: #{daily_cost.errors.full_messages.join(', ')}"
      end
    end
    
    synced_count
  end
  
  def calculate_total_cost(groups)
    total = 0.0
    
    groups.each do |group|
      # Get the unblended cost amount
      amount = group.metrics['UnblendedCost']['amount'].to_f
      total += amount
    end
    
    total.round(2)
  end
  
  def handle_aws_error(error)
    error_message = case error
    when Aws::CostExplorer::Errors::InvalidNextTokenException
      "Invalid pagination token - data may be incomplete"
    when Aws::CostExplorer::Errors::LimitExceededException
      "AWS API rate limit exceeded - please try again later"
    when Aws::CostExplorer::Errors::RequestChangedException
      "Request parameters changed during processing"
    when Aws::CostExplorer::Errors::UnresolvableUsageUnitException
      "Cannot resolve usage units for cost calculation"
    when Aws::CostExplorer::Errors::InvalidParameterException
      "Invalid request parameters: #{error.message}"
    when Aws::CostExplorer::Errors::DataUnavailableException
      "Cost data is not available for the requested time period"
    else
      "AWS CostExplorer error: #{error.message}"
    end
    
    Rails.logger.error "AWS error for account #{aws_account.name}: #{error_message}"
    failure(error_message)
  end
  
  def handle_generic_error(error)
    error_message = "Unexpected error during cost sync: #{error.message}"
    Rails.logger.error "Generic error for account #{aws_account.name}: #{error_message}"
    Rails.logger.error error.backtrace.join("\n")
    
    failure(error_message)
  end
  
  def success(message)
    {
      success: true,
      message: message,
      synced_dates: (start_date..end_date).count,
      account_id: aws_account.id
    }
  end
  
  def failure(error_message)
    {
      success: false,
      error: error_message,
      synced_dates: 0,
      account_id: aws_account.id
    }
  end
  
  def date_range_valid?
    return unless start_date && end_date
    
    if start_date > end_date
      errors.add(:end_date, "must be after start date")
    end
    
    if start_date < 90.days.ago.to_date
      errors.add(:start_date, "cannot be more than 90 days ago")
    end
    
    if end_date > Date.current
      errors.add(:end_date, "cannot be in the future")
    end
    
    if (end_date - start_date).to_i > 31
      errors.add(:base, "date range cannot exceed 31 days")
    end
  end
  
  def aws_credentials_present?
    return unless aws_account
    
    if aws_account.access_key.blank?
      errors.add(:aws_account, "must have access key")
    end
    
    if aws_account.secret_key.blank?
      errors.add(:aws_account, "must have secret key")  
    end
  end
end