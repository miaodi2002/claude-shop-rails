# frozen_string_literal: true

class AwsAccount < ApplicationRecord
  # Include concerns
  include Auditable
  
  # Encryption for sensitive data
  attr_encrypted :secret_key, 
                 key: ENV.fetch('ATTR_ENCRYPTED_KEY', 'your_32_character_encryption_key_here_123456')[0..31],
                 encode: true,
                 encode_iv: true,
                 encode_salt: true

  # Enums
  enum status: {
    available: 0,
    sold_out: 1,
    maintenance: 2,
    offline: 3
  }

  enum connection_status: {
    connected: 0,
    error: 1,
    unknown: 2
  }

  # Associations
  has_many :quotas, dependent: :destroy
  has_many :quota_histories, dependent: :destroy
  has_many :refresh_jobs, dependent: :nullify
  has_many :audit_logs, as: :target, dependent: :destroy

  # Validations
  validates :account_id, presence: true, uniqueness: true, 
            length: { maximum: 20 },
            format: { with: /\A\d{12}\z/, message: "必须是12位数字的AWS账号ID" }
  
  validates :access_key, presence: true, 
            length: { minimum: 16, maximum: 128 },
            format: { with: /\AAKIA[0-9A-Z]{16,}\z/, message: "不是有效的AWS Access Key格式" }
  
  validates :secret_key, presence: true, length: { minimum: 40 }
  validates :name, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 500 }, allow_blank: true
  
  # Callbacks
  before_validation :set_default_values
  after_create :create_initial_quotas
  after_create :test_connection_async

  # Scopes
  scope :active, -> { where(status: [:available, :maintenance]) }
  scope :public_visible, -> { where(status: :available) }
  scope :with_quotas, -> { includes(:quotas) }
  scope :by_status, ->(status) { where(status: status) }
  scope :search, ->(query) { 
    where("name LIKE :q OR account_id LIKE :q OR description LIKE :q", q: "%#{query}%") 
  }

  # Soft delete
  def soft_delete!
    update!(deleted_at: Time.current, status: :offline)
  end

  def deleted?
    deleted_at.present?
  end

  def restore!
    update!(deleted_at: nil, status: :available)
  end

  # Connection testing
  def test_connection
    # This will be implemented when AWS service is ready
    # For now, return mock result
    update!(
      connection_status: :connected,
      last_connected_at: Time.current
    )
    true
  rescue => e
    update!(
      connection_status: :error,
      connection_error: e.message
    )
    false
  end

  def test_connection_async
    # Queue job for connection testing
    # RefreshQuotaJob.perform_later(self, test_only: true)
  end

  # Quota management
  def total_quota_remaining
    quotas.sum(:quota_remaining)
  end

  def has_quota?
    total_quota_remaining > 0
  end

  def refresh_quotas!
    # This will be implemented with AWS service
    quotas.find_or_create_by(model_name: 'Claude-3.5-Sonnet').update!(
      quota_limit: 1000,
      quota_used: 0,
      quota_remaining: 1000,
      last_updated_at: Time.current
    )
  end

  # Display helpers
  def display_status
    I18n.t("aws_account.status.#{status}")
  end

  def display_connection_status
    I18n.t("aws_account.connection_status.#{connection_status}")
  end

  def masked_access_key
    return '' unless access_key.present?
    "#{access_key[0..3]}...#{access_key[-4..]}"
  end

  def masked_secret_key
    '••••••••••••••••'
  end

  # Claude model availability
  def available_models
    quotas.where('quota_remaining > 0').pluck(:model_name)
  end

  def model_quota(model_name)
    quotas.find_by(model_name: model_name)
  end

  # Auditable configuration
  auditable_fields :name, :account_id, :access_key, :status, :connection_status, :description
  
  def audit_metadata
    {
      account_name: name,
      account_status: status,
      connection_status: connection_status,
      has_quota: has_quota?,
      total_remaining: total_quota_remaining
    }
  end
  
  # Override auditable concern to mask sensitive data
  def filter_auditable_changes(changes)
    filtered_changes = super(changes)
    
    # Mask sensitive data in audit logs
    if filtered_changes['access_key']
      filtered_changes['access_key'] = [masked_access_key, masked_access_key]
    end
    
    # Remove encrypted secret key from logs
    filtered_changes.delete('secret_key_encrypted')
    filtered_changes.delete('secret_key_encrypted_iv')
    
    filtered_changes
  end

  private

  def set_default_values
    self.status ||= :available
    self.connection_status ||= :unknown
  end

  def create_initial_quotas
    # Create default quotas for common Claude models
    %w[Claude-3.5-Sonnet Claude-3-Haiku Claude-3-Opus].each do |model|
      quotas.create!(
        model_name: model,
        quota_limit: 0,
        quota_used: 0,
        quota_remaining: 0
      )
    end
  end
end