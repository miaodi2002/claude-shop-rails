# frozen_string_literal: true

class AwsAccount < ApplicationRecord
  # Include concerns
  include Auditable
  
  # Encryption for sensitive data
  attr_encrypted :secret_key, 
                 key: ENV.fetch('ATTR_ENCRYPTED_KEY', 'your_32_character_encryption_key_here_123456')[0..31],
                 encode: true,
                 algorithm: 'aes-256-cbc',
                 attribute: 'secret_key_encrypted',
                 iv_attribute: 'secret_key_encrypted_iv'

  # Enums
  enum :status, {
    active: 0,
    inactive: 1,
    sold_out: 2,
    maintenance: 3
  }

  enum :connection_status, {
    connected: 0,
    error: 1,
    unknown: 2
  }

  # Associations
  has_many :account_quotas, dependent: :destroy
  has_many :quota_definitions, through: :account_quotas
  has_many :refresh_jobs, dependent: :nullify
  has_many :audit_logs, as: :target, dependent: :destroy

  # Virtual attributes
  def tags
    read_attribute(:tags) || []
  end
  
  def tags=(value)
    if value.is_a?(String)
      write_attribute(:tags, value.split(',').map(&:strip).reject(&:blank?))
    else
      write_attribute(:tags, value)
    end
  end

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
  after_create :test_connection_async

  # Scopes
  scope :active, -> { where(status: :active) }
  scope :public_visible, -> { where(status: :active) }
  scope :with_quotas, -> { includes(:account_quotas, :quota_definitions) }
  scope :by_status, ->(status) { where(status: status) }
  scope :search, ->(query) { 
    where("name LIKE :q OR account_id LIKE :q OR description LIKE :q", q: "%#{query}%") 
  }

  # Soft delete
  def soft_delete!
    update!(deleted_at: Time.current, status: :inactive)
  end

  def deleted?
    deleted_at.present?
  end

  def restore!
    update!(deleted_at: nil, status: :active)
  end

  # Connection testing
  def test_connection
    # This will be implemented when AWS service is ready
    # For now, return mock result
    update!(
      connection_status: :connected,
      last_connection_test_at: Time.current
    )
    true
  rescue => e
    update!(
      connection_status: :error,
      connection_error_message: e.message
    )
    false
  end

  def test_connection_async
    # Queue job for connection testing
    # RefreshQuotaJob.perform_later(self, test_only: true)
  end

  # Quota management
  def has_high_quota?
    account_quotas.high_level.exists?
  end

  def refresh_quotas!
    AwsQuotaService.refresh_all_quotas(self)
  end

  # Display helpers
  def display_status
    I18n.t("aws_account.status.#{status}")
  end

  def display_connection_status
    I18n.t("aws_account.connection_status.#{connection_status}")
  end

  # Alias for compatibility with views
  def account_name
    name
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
    account_quotas.joins(:quota_definition)
                  .where('current_quota > 0')
                  .pluck('quota_definitions.claude_model_name')
                  .uniq
  end

  def model_quotas(model_name)
    account_quotas.by_model(model_name)
  end

  # Auditable configuration
  auditable_fields :name, :account_id, :access_key, :status, :connection_status, :description
  
  def audit_metadata
    {
      account_name: name,
      account_status: status,
      connection_status: connection_status,
      has_high_quota: has_high_quota?,
      total_quotas: account_quotas.count
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
    filtered_changes.delete('secret_access_key_encrypted')
    filtered_changes.delete('secret_access_key_encrypted_iv')
    
    filtered_changes
  end

  private

  def set_default_values
    self.status ||= :active
    self.connection_status ||= :unknown
  end
end