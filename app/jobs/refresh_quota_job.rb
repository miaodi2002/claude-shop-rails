# frozen_string_literal: true

class RefreshQuotaJob < ApplicationJob
  queue_as :default
  
  # Retry configuration
  retry_on StandardError, wait: 30.seconds, attempts: 3
  retry_on Aws::Errors::ServiceError, wait: 1.minute, attempts: 5
  
  # Discard job if account is deleted or inactive
  discard_on ActiveRecord::RecordNotFound
  
  def perform(aws_account_id = nil, options = {})
    if aws_account_id
      # Refresh single account
      refresh_single_account(aws_account_id, options)
    else
      # Refresh all active accounts
      refresh_all_accounts(options)
    end
  end
  
  private
  
  def refresh_single_account(aws_account_id, options = {})
    aws_account = AwsAccount.find(aws_account_id)
    
    # Skip if account is not active
    unless aws_account.active?
      Rails.logger.info "Skipping inactive account: #{aws_account.account_id}"
      return
    end
    
    # Create refresh job record
    refresh_job = RefreshJob.create_single_job(aws_account, job_type: options[:job_type] || :automatic)
    refresh_job.start!
    
    # Update progress to indicate job has started
    refresh_job.update_progress(0)
    
    begin
      # Set audit context
      AuditContextService.set_context(admin: nil)
      
      # Update progress to 50% before starting refresh
      refresh_job.update_progress(0.5)
      
      # Refresh quotas
      result = AwsService.refresh_account_quotas(aws_account)
      
      if result[:success]
        # Update progress to 100% before completion
        refresh_job.update_progress(1.0)
        refresh_job.complete!(1, 0)
        
        # Log success
        AuditContextService.log_action(
          'refresh_quota',
          target: aws_account,
          metadata: {
            job_id: refresh_job.id,
            quotas_updated: result[:quotas].count,
            total_quota: result[:quotas].sum { |q| q[:current_quota] || 0 }
          }
        )
        
        Rails.logger.info "Successfully refreshed quotas for account: #{aws_account.account_id}"
      else
        refresh_job.fail!(result[:error])
        
        # Log failure
        AuditContextService.log_action(
          'refresh_quota_failed',
          target: aws_account,
          metadata: {
            job_id: refresh_job.id,
            error: result[:error],
            error_code: result[:error_code]
          }
        )
        
        Rails.logger.error "Failed to refresh quotas for account #{aws_account.account_id}: #{result[:error]}"
      end
      
    rescue => e
      refresh_job.fail!(e.message)
      
      # Log exception
      AuditContextService.log_action(
        'refresh_quota_error',
        target: aws_account,
        metadata: {
          job_id: refresh_job.id,
          error: e.message,
          backtrace: e.backtrace.first(5)
        }
      )
      
      Rails.logger.error "Exception during quota refresh for account #{aws_account.account_id}: #{e.message}"
      raise # Re-raise for retry mechanism
    ensure
      AuditContextService.clear_context
    end
  end
  
  def refresh_all_accounts(options = {})
    accounts = AwsAccount.active.includes(:account_quotas)
    
    # Skip if no accounts
    if accounts.empty?
      Rails.logger.info "No active AWS accounts found for quota refresh"
      return
    end
    
    # Create batch refresh job record
    refresh_job = RefreshJob.create_batch_job(job_type: options[:job_type] || :automatic)
    refresh_job.start!
    
    begin
      # Set audit context
      AuditContextService.set_context(admin: nil)
      
      # Refresh quotas for all accounts
      results = AwsService.refresh_batch_quotas(accounts, refresh_job)
      
      refresh_job.complete!(results[:successful], results[:failed])
      
      # Log batch results
      AuditContextService.log_action(
        'refresh_quota_batch',
        metadata: {
          job_id: refresh_job.id,
          total_accounts: results[:total],
          successful: results[:successful],
          failed: results[:failed],
          errors: results[:errors].first(10) # Limit errors in logs
        }
      )
      
      Rails.logger.info "Batch quota refresh completed: #{results[:successful]}/#{results[:total]} successful"
      
      # Send notifications if there are failures
      if results[:failed] > 0
        send_failure_notifications(results)
      end
      
    rescue => e
      refresh_job.fail!(e.message)
      
      # Log exception
      AuditContextService.log_action(
        'refresh_quota_batch_error',
        metadata: {
          job_id: refresh_job.id,
          error: e.message,
          total_accounts: accounts.count
        }
      )
      
      Rails.logger.error "Exception during batch quota refresh: #{e.message}"
      raise # Re-raise for retry mechanism
    ensure
      AuditContextService.clear_context
    end
  end
  
  def send_failure_notifications(results)
    # This could be extended to send email, Slack, or other notifications
    if results[:failed] > 5
      Rails.logger.warn "High failure rate in quota refresh: #{results[:failed]}/#{results[:total]} accounts failed"
    end
    
    # Log individual failures
    results[:errors].each do |error|
      Rails.logger.warn "Account #{error[:account_id]} (#{error[:account_name]}) failed: #{error[:error]}"
    end
  end
end