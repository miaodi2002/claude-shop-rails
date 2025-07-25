# == Schema Information
#
# Table name: aws_accounts
#
#  id                           :bigint           not null, primary key
#  account_id                   :string(20)       not null
#  access_key                   :string(100)      not null
#  secret_key_encrypted         :text(65535)      not null
#  secret_key_encrypted_iv      :string(255)      not null
#  name                         :string(100)      not null
#  description                  :text(65535)
#  status                       :integer          default("available"), not null
#  connection_status            :integer          default("unknown"), not null
#  connection_error_message     :text(65535)
#  last_connection_test_at      :datetime
#  last_quota_update_at         :datetime
#  deleted_at                   :datetime
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#

class AwsAccount < ApplicationRecord
  # 加密敏感字段
  attr_encrypted :secret_key, key: Rails.application.credentials.secret_key_base

  # 关联
  has_many :quotas, dependent: :destroy
  has_many :quota_histories, dependent: :destroy
  has_many :audit_logs, as: :target, dependent: :nullify
  has_many :refresh_jobs, dependent: :destroy

  # 枚举
  enum status: {
    available: 0,    # 可用
    sold_out: 1,     # 售罄
    maintenance: 2,  # 维护中
    offline: 3       # 已下架
  }

  enum connection_status: {
    connected: 0,    # 连接正常
    error: 1,        # 连接错误
    unknown: 2       # 未知状态
  }

  # 验证
  validates :account_id, presence: true, uniqueness: true, length: { maximum: 20 }
  validates :access_key, presence: true, length: { maximum: 100 }
  validates :secret_key, presence: true
  validates :name, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 1000 }

  # 作用域
  scope :active, -> { where(deleted_at: nil) }
  scope :public_visible, -> { active.where(status: [:available, :sold_out]) }
  scope :with_quotas, -> { joins(:quotas).distinct }
  scope :by_model, ->(model_name) { joins(:quotas).where(quotas: { model_name: model_name }) }
  scope :with_available_quota, -> { 
    joins(:quotas).where('quotas.quota_remaining > 0').distinct 
  }

  # 回调
  before_destroy :soft_delete
  after_create :schedule_quota_refresh
  after_update :log_status_change, if: :saved_change_to_status?

  # 软删除
  def destroy
    update_column(:deleted_at, Time.current)
  end

  def destroyed?
    deleted_at.present?
  end

  # 业务方法
  def display_name
    "#{name} (#{account_id})"
  end

  def total_quota_remaining
    quotas.sum(:quota_remaining)
  end

  def has_available_quota?
    total_quota_remaining > 0
  end

  def models_with_quota
    quotas.where('quota_remaining > 0').pluck(:model_name)
  end

  def quota_status_color
    case status
    when 'available'
      has_available_quota? ? 'green' : 'yellow'
    when 'sold_out'
      'red'
    when 'maintenance'
      'orange'
    else
      'gray'
    end
  end

  def connection_healthy?
    connected? && last_connection_test_at&.> 1.hour.ago
  end

  def needs_quota_refresh?
    last_quota_update_at.nil? || last_quota_update_at < 1.hour.ago
  end

  # AWS 连接测试
  def test_connection!
    begin
      result = Aws::ConnectionTester.new(self).test
      update!(
        connection_status: result[:success] ? 'connected' : 'error',
        connection_error_message: result[:error],
        last_connection_test_at: Time.current
      )
      result[:success]
    rescue => e
      update!(
        connection_status: 'error',
        connection_error_message: e.message,
        last_connection_test_at: Time.current
      )
      false
    end
  end

  # 刷新配额
  def refresh_quota!(force: false)
    return false unless connected? || force

    QuotaRefreshJob.perform_later(self.id)
  end

  # 批量操作
  def self.refresh_all_quotas
    active.connected.find_each do |account|
      account.refresh_quota!
    end
  end

  def self.test_all_connections
    active.find_each(&:test_connection!)
  end

  private

  def soft_delete
    throw :abort
  end

  def schedule_quota_refresh
    QuotaRefreshJob.perform_later(id)
  end

  def log_status_change
    AuditLoggerService.log(
      action: 'status_change',
      target: self,
      changes: { status: saved_changes['status'] },
      admin: Current.admin
    )
  end
end