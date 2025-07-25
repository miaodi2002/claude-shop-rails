# frozen_string_literal: true

class QuotaSchedulerService
  # Default refresh intervals
  DEFAULT_INTERVAL = 1.hour
  MANUAL_COOLDOWN = 5.minutes
  
  class << self
    # Schedule automatic refresh for all accounts
    def schedule_automatic_refresh
      interval = SystemConfig.get('aws.quota_refresh_interval', DEFAULT_INTERVAL.to_i).seconds
      
      # Check if there's already a scheduled job within the interval
      return if recent_automatic_job_exists?(interval)
      
      # Queue the job
      RefreshQuotaJob.set(wait: 30.seconds).perform_later(nil, job_type: :automatic)
      
      Rails.logger.info "Scheduled automatic quota refresh in 30 seconds"
    end
    
    # Schedule refresh for specific account
    def schedule_account_refresh(aws_account, job_type: :manual, delay: 0)
      # Check cooldown for manual refreshes
      if job_type == :manual && account_in_cooldown?(aws_account)
        cooldown_remaining = cooldown_remaining_time(aws_account)
        raise "Account is in cooldown. Please wait #{cooldown_remaining} before refreshing again."
      end
      
      # Queue the job
      if delay > 0
        RefreshQuotaJob.set(wait: delay.seconds).perform_later(aws_account.id, job_type: job_type)
      else
        RefreshQuotaJob.perform_later(aws_account.id, job_type: job_type)
      end
      
      Rails.logger.info "Scheduled quota refresh for account: #{aws_account.account_id}"
    end
    
    # Schedule refresh for multiple accounts
    def schedule_batch_refresh(aws_account_ids, job_type: :manual, stagger_delay: true)
      aws_account_ids.each_with_index do |account_id, index|
        delay = stagger_delay ? index * 10 : 0 # 10 second stagger
        
        aws_account = AwsAccount.find(account_id)
        schedule_account_refresh(aws_account, job_type: job_type, delay: delay)
      end
      
      Rails.logger.info "Scheduled batch quota refresh for #{aws_account_ids.count} accounts"
    end
    
    # Setup recurring automatic refresh
    def setup_recurring_refresh
      # This would typically be done with a cron job or scheduler like whenever gem
      # For now, we'll use a simple approach with Sidekiq-cron if available
      
      interval = SystemConfig.get('aws.quota_refresh_interval', DEFAULT_INTERVAL.to_i)
      
      if defined?(Sidekiq::Cron::Job)
        # Convert seconds to cron format (simplified)
        cron_expression = seconds_to_cron(interval)
        
        Sidekiq::Cron::Job.create(
          name: 'Automatic Quota Refresh',
          cron: cron_expression,
          klass: 'RefreshQuotaJob',
          args: [nil, { job_type: :automatic }]
        )
        
        Rails.logger.info "Setup recurring quota refresh with interval: #{interval} seconds"
      else
        Rails.logger.warn "Sidekiq-cron not available. Manual scheduling required."
      end
    end
    
    # Get next scheduled refresh time
    def next_refresh_time
      last_automatic = RefreshJob.where(job_type: :automatic)
                                .order(created_at: :desc)
                                .first
      
      if last_automatic
        interval = SystemConfig.get('aws.quota_refresh_interval', DEFAULT_INTERVAL.to_i).seconds
        last_automatic.created_at + interval
      else
        Time.current + DEFAULT_INTERVAL
      end
    end
    
    # Get refresh statistics
    def refresh_statistics(period: 24.hours)
      since = period.ago
      
      total_jobs = RefreshJob.where('created_at >= ?', since)
      
      {
        period_hours: (period / 1.hour).round(1),
        total_jobs: total_jobs.count,
        successful_jobs: total_jobs.completed.count,
        failed_jobs: total_jobs.failed.count,
        success_rate: calculate_success_rate(total_jobs),
        avg_duration: calculate_average_duration(total_jobs.completed),
        accounts_refreshed: total_jobs.joins(:aws_account).distinct.count('aws_accounts.id'),
        last_refresh: total_jobs.maximum(:created_at)
      }
    end
    
    # Health check for quota refresh system
    def health_check
      issues = []
      
      # Check if automatic refresh is working
      last_automatic = RefreshJob.where(job_type: :automatic)
                                .order(created_at: :desc)
                                .first
      
      if last_automatic.nil?
        issues << "No automatic refresh jobs found"
      elsif last_automatic.created_at < 2.hours.ago
        issues << "Last automatic refresh was more than 2 hours ago"
      end
      
      # Check failure rate
      recent_jobs = RefreshJob.where('created_at >= ?', 6.hours.ago)
      if recent_jobs.any?
        failure_rate = (recent_jobs.failed.count.to_f / recent_jobs.count * 100).round(2)
        if failure_rate > 20
          issues << "High failure rate: #{failure_rate}%"
        end
      end
      
      # Check AWS credentials
      test_account = AwsAccount.active.first
      if test_account
        begin
          result = AwsService.test_credentials(
            test_account.access_key,
            test_account.secret_key
          )
          unless result[:success]
            issues << "AWS credentials test failed: #{result[:error]}"
          end
        rescue => e
          issues << "Error testing AWS credentials: #{e.message}"
        end
      else
        issues << "No active AWS accounts for testing"
      end
      
      {
        healthy: issues.empty?,
        issues: issues,
        checked_at: Time.current
      }
    end
    
    private
    
    def recent_automatic_job_exists?(interval)
      RefreshJob.where(job_type: :automatic)
               .where('created_at >= ?', interval.ago)
               .exists?
    end
    
    def account_in_cooldown?(aws_account)
      last_refresh = RefreshJob.where(
        aws_account: aws_account,
        job_type: :manual
      ).order(created_at: :desc).first
      
      return false unless last_refresh
      
      last_refresh.created_at > MANUAL_COOLDOWN.ago
    end
    
    def cooldown_remaining_time(aws_account)
      last_refresh = RefreshJob.where(
        aws_account: aws_account,
        job_type: :manual
      ).order(created_at: :desc).first
      
      return 0 unless last_refresh
      
      remaining_seconds = MANUAL_COOLDOWN.to_i - (Time.current - last_refresh.created_at).to_i
      [remaining_seconds, 0].max
    end
    
    def seconds_to_cron(seconds)
      # Simple conversion - in production, use proper cron expression
      minutes = seconds / 60
      
      case minutes
      when 0..59
        "*/#{minutes} * * * *"
      when 60..1439
        hours = minutes / 60
        "0 */#{hours} * * *"
      else
        "0 0 * * *" # Daily if more than 24 hours
      end
    end
    
    def calculate_success_rate(jobs)
      return 0 if jobs.empty?
      
      completed_count = jobs.completed.count
      (completed_count.to_f / jobs.count * 100).round(2)
    end
    
    def calculate_average_duration(completed_jobs)
      return 0 if completed_jobs.empty?
      
      durations = completed_jobs.map(&:duration).compact
      return 0 if durations.empty?
      
      (durations.sum / durations.count).round(2)
    end
  end
end