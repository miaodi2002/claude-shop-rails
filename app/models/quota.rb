# frozen_string_literal: true

class Quota < ApplicationRecord
  # Associations
  belongs_to :aws_account
  has_many :quota_histories, dependent: :destroy

  # Validations
  validates :model_name, presence: true, 
            length: { maximum: 100 },
            uniqueness: { scope: :aws_account_id }
  
  validates :quota_limit, :quota_used, :quota_remaining, 
            presence: true,
            numericality: { greater_than_or_equal_to: 0 }

  validate :quota_consistency

  # Callbacks
  before_save :calculate_remaining
  after_update :create_history_record, if: :quota_changed?

  # Scopes
  scope :with_remaining, -> { where('quota_remaining > 0') }
  scope :exhausted, -> { where(quota_remaining: 0) }
  scope :by_model, ->(model_name) { where(model_name: model_name) }
  scope :recently_updated, -> { where('last_updated_at > ?', 24.hours.ago) }

  # Update status enum
  enum update_status: {
    success: 0,
    failed: 1,
    pending: 2
  }

  # Class methods
  def self.total_remaining_by_model
    group(:model_name).sum(:quota_remaining)
  end

  def self.update_from_api_response(aws_account, api_data)
    api_data.each do |model_data|
      quota = find_or_initialize_by(
        aws_account: aws_account,
        model_name: model_data[:model_name]
      )
      
      quota.update!(
        quota_limit: model_data[:limit],
        quota_used: model_data[:used],
        quota_remaining: model_data[:limit] - model_data[:used],
        last_updated_at: Time.current,
        update_status: :success
      )
    end
  end

  # Instance methods
  def usage_percentage
    return 0 if quota_limit.zero?
    ((quota_used.to_f / quota_limit) * 100).round(2)
  end

  def remaining_percentage
    return 0 if quota_limit.zero?
    ((quota_remaining.to_f / quota_limit) * 100).round(2)
  end

  def exhausted?
    quota_remaining.zero?
  end

  def nearly_exhausted?
    remaining_percentage < 10
  end

  def healthy?
    remaining_percentage >= 50
  end

  def status_indicator
    case remaining_percentage
    when 0 then :exhausted
    when 0..10 then :critical
    when 10..30 then :warning
    when 30..50 then :moderate
    else :healthy
    end
  end

  def refresh!
    # This will be implemented when AWS service is ready
    # For now, simulate refresh
    simulate_refresh
  end

  def mark_as_failed!(error_message = nil)
    update!(
      update_status: :failed,
      metadata: { error: error_message, failed_at: Time.current }
    )
  end

  private

  def calculate_remaining
    self.quota_remaining = [quota_limit - quota_used, 0].max
  end

  def quota_consistency
    if quota_used > quota_limit
      errors.add(:quota_used, "不能超过配额限制")
    end

    if quota_remaining > quota_limit
      errors.add(:quota_remaining, "不能超过配额限制")
    end
  end

  def quota_changed?
    saved_change_to_quota_limit? || 
    saved_change_to_quota_used? || 
    saved_change_to_quota_remaining?
  end

  def create_history_record
    QuotaHistory.create!(
      aws_account: aws_account,
      quota: self,
      model_name: model_name,
      quota_limit: quota_limit,
      quota_used: quota_used,
      quota_remaining: quota_remaining,
      recorded_at: Time.current
    )
  rescue => e
    Rails.logger.error "Failed to create quota history: #{e.message}"
  end

  def simulate_refresh
    # Simulate API call with random data
    new_used = quota_used + rand(0..10)
    new_used = [new_used, quota_limit].min
    
    update!(
      quota_used: new_used,
      quota_remaining: quota_limit - new_used,
      last_updated_at: Time.current,
      update_status: :success
    )
  end
end