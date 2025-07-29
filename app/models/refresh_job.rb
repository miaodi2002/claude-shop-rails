# frozen_string_literal: true

class RefreshJob < ApplicationRecord
  # Associations
  belongs_to :aws_account, optional: true

  # Enums
  enum :job_type, {
    manual: 'manual',
    automatic: 'automatic', 
    scheduled: 'scheduled',
    bulk_refresh: 'bulk_refresh'
  }

  enum :status, {
    pending: 0,
    running: 1,
    completed: 2,
    failed: 3,
    cancelled: 4,
    partially_completed: 5
  }

  # Validations
  validates :job_type, presence: true
  validates :status, presence: true
  validates :total_accounts, numericality: { greater_than_or_equal_to: 0 }
  validates :successful_accounts, numericality: { greater_than_or_equal_to: 0 }
  validates :failed_accounts, numericality: { greater_than_or_equal_to: 0 }

  # Callbacks
  before_create :set_defaults
  after_update :update_completion_time

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :in_progress, -> { where(status: [:pending, :running]) }
  scope :finished, -> { where(status: [:completed, :failed, :cancelled]) }
  scope :for_account, ->(account) { where(aws_account: account) }

  # Class methods
  def self.create_batch_job(job_type: :manual)
    create!(
      job_type: job_type,
      total_accounts: AwsAccount.active.count
    )
  end

  def self.create_single_job(aws_account, job_type: :manual)
    create!(
      aws_account: aws_account,
      job_type: job_type,
      total_accounts: 1
    )
  end

  def self.cleanup_old_jobs(days_to_keep = 30)
    where('created_at < ?', days_to_keep.days.ago).delete_all
  end

  # Instance methods
  def batch_job?
    aws_account.nil?
  end

  def single_account_job?
    aws_account.present?
  end

  def start!
    update!(
      status: :running,
      started_at: Time.current
    )
  end

  def complete!(success_count = 0, failure_count = 0)
    update!(
      status: :completed,
      completed_at: Time.current,
      successful_accounts: success_count,
      failed_accounts: failure_count
    )
  end

  def fail!(error_message)
    update!(
      status: :failed,
      completed_at: Time.current,
      error_message: error_message
    )
  end

  def cancel!
    return unless pending? || running?
    
    update!(
      status: :cancelled,
      completed_at: Time.current
    )
  end

  def update_progress(processed_count)
    return unless running?
    return if total_accounts.zero?

    update!(processed_accounts: processed_count)
  end
  
  def progress_percentage
    return 0 if total_accounts.zero?
    [(processed_accounts.to_f / total_accounts * 100).round(2), 100].min
  end

  def duration
    return nil unless started_at.present?
    
    end_time = completed_at || Time.current
    end_time - started_at
  end

  def duration_in_words
    return '未开始' unless started_at.present?
    
    seconds = duration
    return '计算中...' unless seconds
    
    if seconds < 60
      "#{seconds.round}秒"
    elsif seconds < 3600
      "#{(seconds / 60).round}分钟"
    else
      "#{(seconds / 3600).round(1)}小时"
    end
  end

  def success_rate
    return 0 if total_accounts.zero?
    (successful_accounts.to_f / total_accounts * 100).round(2)
  end

  def failure_rate
    return 0 if total_accounts.zero?
    (failed_accounts.to_f / total_accounts * 100).round(2)
  end

  def can_cancel?
    pending? || running?
  end

  def can_retry?
    failed? || cancelled?
  end

  def display_status
    I18n.t("refresh_job.status.#{status}")
  end

  def display_job_type
    I18n.t("refresh_job.job_type.#{job_type}")
  end

  def summary
    if batch_job?
      "批量刷新 #{total_accounts} 个账号"
    else
      "刷新账号 #{aws_account&.name}"
    end
  end

  def detailed_result
    if completed?
      "成功: #{successful_accounts}, 失败: #{failed_accounts}"
    elsif failed?
      "失败: #{error_message}"
    elsif cancelled?
      "已取消"
    else
      "进行中: #{progress_percentage}%"
    end
  end

  private

  def set_defaults
    self.successful_accounts = 0
    self.failed_accounts = 0
  end

  def update_completion_time
    if status_changed? && (completed? || failed? || cancelled?)
      self.completed_at = Time.current unless completed_at.present?
    end
  end
end