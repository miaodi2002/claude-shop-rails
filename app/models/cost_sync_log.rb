# frozen_string_literal: true

class CostSyncLog < ApplicationRecord
  belongs_to :aws_account, optional: true
  
  # Enums
  enum :status, {
    pending: 0,
    running: 1,
    completed: 2,
    failed: 3
  }, prefix: true
  
  enum :sync_type, {
    single_account: 0,
    batch_sync: 1
  }, prefix: true
  
  # Validations
  validates :status, presence: true
  validates :sync_type, presence: true
  validates :synced_dates_count, numericality: { 
    greater_than_or_equal_to: 0 
  }
  
  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :failed_logs, -> { where(status: :failed) }
  scope :successful_logs, -> { where(status: :completed) }
  scope :for_account, ->(account_id) { where(aws_account_id: account_id) }
  
  # Instance methods
  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end
  
  def success?
    status_completed?
  end
  
  def in_progress?
    status_running?
  end
  
  def formatted_duration
    return 'N/A' unless duration
    Time.at(duration).utc.strftime('%M:%S')
  end
  
  def short_error
    return nil unless error_message
    error_message.truncate(100)
  end
  
  # Class methods
  def self.success_rate(account_id = nil)
    scope = account_id ? for_account(account_id) : all
    total = scope.where.not(status: :pending).count
    return 0.0 if total.zero?
    
    successful = scope.successful_logs.count
    (successful.to_f / total * 100).round(2)
  end
  
  def self.average_duration(account_id = nil)
    scope = account_id ? for_account(account_id) : all
    logs_with_duration = scope.successful_logs
                             .where.not(started_at: nil, completed_at: nil)
    
    return 0.0 if logs_with_duration.empty?
    
    total_duration = logs_with_duration.sum { |log| log.duration || 0 }
    (total_duration / logs_with_duration.count).round(2)
  end
  
  def self.cleanup_old_logs(days = 30)
    where('created_at < ?', days.days.ago).destroy_all
  end
end