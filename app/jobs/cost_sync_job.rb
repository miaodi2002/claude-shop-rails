# frozen_string_literal: true

class CostSyncJob
  include Sidekiq::Job
  
  # Job configuration - retry disabled for now
  sidekiq_options queue: 'cost_sync', retry: false, backtrace: 5
  
  # Execute the job
  def perform(aws_account_id, start_date = nil, end_date = nil)
    @aws_account = AwsAccount.find(aws_account_id)
    @start_date = start_date ? Date.parse(start_date.to_s) : 2.weeks.ago.to_date
    @end_date = end_date ? Date.parse(end_date.to_s) : Date.current
    
    Rails.logger.info "Starting cost sync job for account #{@aws_account.name}"
    
    # Create sync log
    sync_log = create_sync_log
    
    begin
      # Update log to running
      sync_log.update!(
        status: :running,
        started_at: Time.current
      )
      
      # Execute the sync
      result = perform_sync
      
      # Update log based on result
      if result[:success]
        sync_log.update!(
          status: :completed,
          completed_at: Time.current,
          synced_dates_count: result[:synced_dates]
        )
        
        Rails.logger.info "Cost sync completed for account #{@aws_account.name}: #{result[:message]}"
      else
        sync_log.update!(
          status: :failed,
          completed_at: Time.current,
          error_message: result[:error],
          synced_dates_count: result[:synced_dates] || 0
        )
        
        Rails.logger.error "Cost sync failed for account #{@aws_account.name}: #{result[:error]}"
      end
      
    rescue StandardError => e
      # Handle unexpected errors
      sync_log.update!(
        status: :failed,
        completed_at: Time.current,
        error_message: "Unexpected job error: #{e.message}",
        synced_dates_count: 0
      )
      
      Rails.logger.error "Cost sync job error for account #{@aws_account.name}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Re-raise to let Sidekiq handle it
      raise e
    end
  end
  
  # Class method to enqueue job
  def self.sync_account(aws_account_id, start_date = nil, end_date = nil)
    perform_async(aws_account_id, start_date&.to_s, end_date&.to_s)
  end
  
  # Class method to get job status
  def self.job_status(job_id)
    # This would require sidekiq-status gem for detailed status
    # For now, we use sync logs to track status
    nil
  end
  
  private
  
  def create_sync_log
    @aws_account.cost_sync_logs.create!(
      sync_type: :single_account,
      status: :pending
    )
  end
  
  def perform_sync
    service = AwsCostExplorerService.new(
      aws_account: @aws_account,
      start_date: @start_date,
      end_date: @end_date
    )
    
    # Use sync_with_retry which handles the retry logic
    service.sync_with_retry
  end
  
  # Job retry logic (called by Sidekiq if retry is enabled)
  def self.sidekiq_retry_in(count, exception)
    # We handle retries manually in the service, so disable Sidekiq retries
    nil
  end
  
  # Job failure callback
  def self.sidekiq_retries_exhausted_block
    proc do |msg, exception|
      job_args = msg['args']
      account_id = job_args[0]
      
      Rails.logger.error "Cost sync job exhausted retries for account #{account_id}: #{exception.message}"
      
      # Could send notification email here
      # CostSyncNotificationMailer.sync_failed(account_id, exception.message).deliver_now
    end
  end
end