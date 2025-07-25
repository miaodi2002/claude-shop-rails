# frozen_string_literal: true

class QuotaHistory < ApplicationRecord
  # Associations
  belongs_to :aws_account
  belongs_to :quota

  # Validations
  validates :model_name, presence: true, length: { maximum: 100 }
  validates :quota_limit, :quota_used, :quota_remaining, 
            presence: true,
            numericality: { greater_than_or_equal_to: 0 }
  validates :recorded_at, presence: true

  # Callbacks
  before_validation :set_recorded_at

  # Scopes
  scope :recent, -> { order(recorded_at: :desc) }
  scope :for_model, ->(model_name) { where(model_name: model_name) }
  scope :for_period, ->(start_date, end_date) { 
    where(recorded_at: start_date..end_date) 
  }
  scope :daily_snapshots, -> {
    select("DATE(recorded_at) as snapshot_date, *")
      .group("DATE(recorded_at), id")
      .order("snapshot_date DESC")
  }

  # Class methods
  def self.usage_trend(aws_account, model_name, days = 7)
    for_account = where(aws_account: aws_account)
    for_account = for_account.for_model(model_name) if model_name.present?
    
    for_account
      .for_period(days.days.ago, Time.current)
      .group("DATE(recorded_at)")
      .average(:quota_used)
  end

  def self.create_snapshot(quota)
    create!(
      aws_account: quota.aws_account,
      quota: quota,
      model_name: quota.model_name,
      quota_limit: quota.quota_limit,
      quota_used: quota.quota_used,
      quota_remaining: quota.quota_remaining,
      recorded_at: Time.current
    )
  end

  def self.cleanup_old_records(days_to_keep = 90)
    where('recorded_at < ?', days_to_keep.days.ago).delete_all
  end

  # Instance methods
  def usage_percentage
    return 0 if quota_limit.zero?
    ((quota_used.to_f / quota_limit) * 100).round(2)
  end

  def usage_change_from(previous_record)
    return nil unless previous_record
    quota_used - previous_record.quota_used
  end

  def time_since_previous(previous_record)
    return nil unless previous_record
    recorded_at - previous_record.recorded_at
  end

  private

  def set_recorded_at
    self.recorded_at ||= Time.current
  end
end