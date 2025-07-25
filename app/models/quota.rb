# == Schema Information
#
# Table name: quotas
#
#  id                    :bigint           not null, primary key  
#  aws_account_id        :bigint           not null
#  model_name            :string(100)      not null
#  quota_limit           :bigint           default(0), not null
#  quota_used            :bigint           default(0), not null
#  quota_remaining       :bigint           default(0), not null
#  last_updated_at       :datetime
#  update_status         :integer          default("pending"), not null
#  update_error_message  :text(65535)
#  raw_data              :json
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#

class Quota < ApplicationRecord
  # 关联
  belongs_to :aws_account
  has_many :quota_histories, dependent: :destroy

  # 枚举
  enum update_status: {
    success: 0,      # 更新成功
    failed: 1,       # 更新失败
    pending: 2       # 等待更新
  }

  # 验证
  validates :model_name, presence: true, length: { maximum: 100 }
  validates :quota_limit, numericality: { greater_than_or_equal_to: 0 }
  validates :quota_used, numericality: { greater_than_or_equal_to: 0 }
  validates :quota_remaining, numericality: { greater_than_or_equal_to: 0 }
  validates :aws_account_id, uniqueness: { scope: :model_name }

  # 作用域
  scope :with_remaining, -> { where('quota_remaining > 0') }
  scope :by_model, ->(model) { where(model_name: model) }
  scope :recently_updated, -> { where('last_updated_at > ?', 1.hour.ago) }
  scope :needs_update, -> { where('last_updated_at IS NULL OR last_updated_at < ?', 1.hour.ago) }

  # 回调
  before_save :calculate_remaining
  after_update :create_history_record, if: :saved_change_to_quota_used?

  # 业务方法
  def usage_percentage
    return 0 if quota_limit.zero?
    (quota_used.to_f / quota_limit * 100).round(2)
  end

  def availability_status
    case quota_remaining
    when 0
      'depleted'
    when 1...(quota_limit * 0.1)
      'low'
    when (quota_limit * 0.1)...(quota_limit * 0.5)
      'medium'
    else
      'high'
    end
  end

  def status_color
    case availability_status
    when 'depleted' then 'red'
    when 'low' then 'orange'
    when 'medium' then 'yellow'
    when 'high' then 'green'
    end
  end

  def formatted_quota_limit
    format_number(quota_limit)
  end

  def formatted_quota_used
    format_number(quota_used)
  end

  def formatted_quota_remaining
    format_number(quota_remaining)
  end

  def outdated?
    last_updated_at.nil? || last_updated_at < 1.hour.ago
  end

  def recently_failed?
    failed? && updated_at > 10.minutes.ago
  end

  # 更新配额数据
  def update_from_aws!(data)
    transaction do
      update!(
        quota_limit: data[:limit] || 0,
        quota_used: data[:used] || 0,
        quota_remaining: data[:remaining] || 0,
        last_updated_at: Time.current,
        update_status: 'success',
        update_error_message: nil,
        raw_data: data
      )
      
      # 创建历史记录
      create_history_record
    end
  rescue => e
    update!(
      update_status: 'failed',
      update_error_message: e.message
    )
    raise
  end

  # 类方法
  def self.available_models
    distinct.pluck(:model_name).sort
  end

  def self.total_remaining_by_model
    group(:model_name).sum(:quota_remaining)
  end

  def self.usage_statistics
    {
      total_accounts: joins(:aws_account).distinct.count,
      total_models: distinct.count(:model_name),
      total_quota_limit: sum(:quota_limit),
      total_quota_used: sum(:quota_used),
      total_quota_remaining: sum(:quota_remaining),
      average_usage: average(:quota_used).to_f.round(2)
    }
  end

  def self.refresh_all(account_ids: nil)
    scope = account_ids ? where(aws_account_id: account_ids) : all
    
    scope.includes(:aws_account).find_each(batch_size: 10) do |quota|
      next unless quota.aws_account.connection_healthy?
      
      QuotaRefreshJob.perform_later(quota.aws_account_id, quota.model_name)
    end
  end

  private

  def calculate_remaining
    self.quota_remaining = [quota_limit - quota_used, 0].max
  end

  def create_history_record
    quota_histories.create!(
      aws_account: aws_account,
      model_name: model_name,
      quota_limit: quota_limit,
      quota_used: quota_used,
      quota_remaining: quota_remaining,
      raw_data: raw_data,
      recorded_at: Time.current
    )
  end

  def format_number(number)
    case number
    when 0...1_000
      number.to_s
    when 1_000...1_000_000
      "#{(number / 1_000.0).round(1)}K"
    when 1_000_000...1_000_000_000
      "#{(number / 1_000_000.0).round(1)}M"
    else
      "#{(number / 1_000_000_000.0).round(1)}B"
    end
  end
end