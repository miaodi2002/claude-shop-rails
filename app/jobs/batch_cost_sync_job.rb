# frozen_string_literal: true

class BatchCostSyncJob
  include Sidekiq::Job
  
  # Job configuration - retry disabled for now
  sidekiq_options queue: 'batch_sync', retry: false, backtrace: 5
  
  # Execute the batch job
  def perform(account_ids = nil, start_date = nil, end_date = nil, max_concurrency = 3)
    @account_ids = account_ids || AwsAccount.active.pluck(:id)
    @start_date = start_date ? Date.parse(start_date.to_s) : 2.weeks.ago.to_date
    @end_date = end_date ? Date.parse(end_date.to_s) : Date.current
    @max_concurrency = [max_concurrency.to_i, 5].min # Cap at 5 concurrent jobs
    
    Rails.logger.info "Starting batch cost sync for #{@account_ids.count} accounts"
    
    # Create batch sync log
    sync_log = create_batch_sync_log
    
    begin
      # Update log to running
      sync_log.update!(
        status: :running,
        started_at: Time.current
      )
      
      # Execute parallel sync
      results = perform_parallel_sync
      
      # Analyze results
      successful_count = results.count { |r| r[:success] }
      failed_count = results.count { |r| !r[:success] }
      total_synced_dates = results.sum { |r| r[:synced_dates] || 0 }
      
      # Update log based on overall results
      if failed_count == 0
        sync_log.update!(
          status: :completed,
          completed_at: Time.current,
          synced_dates_count: total_synced_dates
        )
        
        Rails.logger.info "Batch cost sync completed: #{successful_count}/#{@account_ids.count} accounts successful"
      else
        # Collect error messages
        error_messages = results
          .select { |r| !r[:success] }
          .map { |r| "Account #{r[:account_id]}: #{r[:error]}" }
          .join("; ")
        
        sync_log.update!(
          status: :failed,
          completed_at: Time.current,
          error_message: "#{failed_count} accounts failed: #{error_messages}",
          synced_dates_count: total_synced_dates
        )
        
        Rails.logger.error "Batch cost sync completed with errors: #{successful_count}/#{@account_ids.count} successful, #{failed_count} failed"
      end
      
      # Return summary for potential callers
      {
        total_accounts: @account_ids.count,
        successful: successful_count,
        failed: failed_count,
        total_synced_dates: total_synced_dates,
        results: results
      }
      
    rescue StandardError => e
      # Handle unexpected errors
      sync_log.update!(
        status: :failed,
        completed_at: Time.current,
        error_message: "Batch job error: #{e.message}",
        synced_dates_count: 0
      )
      
      Rails.logger.error "Batch cost sync job error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Re-raise to let Sidekiq handle it
      raise e
    end
  end
  
  # Class method to enqueue batch job
  def self.sync_all_accounts(account_ids = nil, start_date = nil, end_date = nil, max_concurrency = 3)
    perform_async(
      account_ids, 
      start_date&.to_s, 
      end_date&.to_s, 
      max_concurrency
    )
  end
  
  # Class method to sync specific accounts
  def self.sync_accounts(account_ids, start_date = nil, end_date = nil, max_concurrency = 3)
    perform_async(
      account_ids, 
      start_date&.to_s, 
      end_date&.to_s, 
      max_concurrency
    )
  end
  
  private
  
  def create_batch_sync_log
    CostSyncLog.create!(
      sync_type: :batch_sync,
      status: :pending,
      aws_account_id: nil # Batch jobs don't belong to a specific account
    )
  end
  
  def perform_parallel_sync
    require 'parallel'
    
    Rails.logger.info "Starting parallel sync with max concurrency: #{@max_concurrency}"
    
    # Use Parallel gem for concurrent processing
    Parallel.map(@account_ids, in_processes: @max_concurrency) do |account_id|
      sync_single_account(account_id)
    end
  rescue LoadError
    # Fallback to sequential processing if Parallel gem not available
    Rails.logger.warn "Parallel gem not available, falling back to sequential processing"
    perform_sequential_sync
  end
  
  def perform_sequential_sync
    Rails.logger.info "Using sequential sync processing"
    
    @account_ids.map do |account_id|
      sync_single_account(account_id)
    end
  end
  
  def sync_single_account(account_id)
    Rails.logger.debug "Syncing account #{account_id}"
    
    begin
      aws_account = AwsAccount.find(account_id)
      
      # Create individual sync log for this account
      sync_log = aws_account.cost_sync_logs.create!(
        sync_type: :single_account,
        status: :running,
        started_at: Time.current
      )
      
      service = AwsCostExplorerService.new(
        aws_account: aws_account,
        start_date: @start_date,
        end_date: @end_date
      )
      
      result = service.sync_with_retry
      
      # Update individual sync log based on result
      if result[:success]
        sync_log.update!(
          status: :completed,
          completed_at: Time.current,
          synced_dates_count: result[:synced_dates]
        )
      else
        sync_log.update!(
          status: :failed,
          completed_at: Time.current,
          error_message: result[:error],
          synced_dates_count: result[:synced_dates] || 0
        )
      end
      
      result[:account_name] = aws_account.name
      result
      
    rescue ActiveRecord::RecordNotFound
      {
        success: false,
        error: "Account not found",
        synced_dates: 0,
        account_id: account_id,
        account_name: "Unknown"
      }
    rescue StandardError => e
      # Update sync log if it was created
      if defined?(sync_log) && sync_log
        sync_log.update!(
          status: :failed,
          completed_at: Time.current,
          error_message: "Sync error: #{e.message}",
          synced_dates_count: 0
        )
      end
      
      {
        success: false,
        error: "Sync error: #{e.message}",
        synced_dates: 0,
        account_id: account_id,
        account_name: "Error"
      }
    end
  end
  
  # Job failure callback
  def self.sidekiq_retries_exhausted_block
    proc do |msg, exception|
      Rails.logger.error "Batch cost sync job exhausted retries: #{exception.message}"
      
      # Could send notification email here
      # CostSyncNotificationMailer.batch_sync_failed(exception.message).deliver_now
    end
  end
end