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
    maintenance: 3,
    for_sale: 4
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

  # Alias for backward compatibility with old quota system
  alias_method :quotas, :account_quotas

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
  validates :account_id, uniqueness: true, allow_blank: true,
            length: { maximum: 20 },
            format: { with: /\A\d{12}\z/, message: "必须是12位数字的AWS账号ID" }
  
  validates :access_key, presence: true, 
            length: { minimum: 16, maximum: 128 },
            format: { with: /\AAKIA[0-9A-Z]{16,}\z/, message: "不是有效的AWS Access Key格式" }
  
  validates :secret_key, presence: true, length: { minimum: 40 }, on: :create
  validates :secret_key, length: { minimum: 40 }, allow_blank: true, on: :update
  validates :name, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 500 }, allow_blank: true
  
  # Callbacks
  before_validation :set_default_values

  # Scopes
  scope :active, -> { where(status: :active) }
  scope :available, -> { active }  # active状态的账号就是可用的
  scope :public_visible, -> { where(status: [:active, :for_sale]) }
  scope :with_quotas, -> { includes(:account_quotas, :quota_definitions) }
  scope :by_status, ->(status) { where(status: status) }
  scope :by_region, ->(region) { where(region: region) }
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

  def masked_account_id
    return '未设置' unless account_id.present?
    "#{account_id[0..7]}****"  # 显示前8位，隐藏后4位
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

  # Quota summary for display
  def quota_summary
    {
      rpm: account_quotas.joins(:quota_definition)
           .where(quota_definitions: { quota_type: 'requests_per_minute' })
           .maximum(:current_quota) || 0,
      tpm: account_quotas.joins(:quota_definition)
           .where(quota_definitions: { quota_type: 'tokens_per_minute' })
           .maximum(:current_quota) || 0,
      tpd: account_quotas.joins(:quota_definition)
           .where(quota_definitions: { quota_type: 'tokens_per_day' })
           .maximum(:current_quota) || 0
    }
  end

  # Format large numbers for display
  def format_quota_value(value)
    return '0' if value.nil? || value == 0
    
    if value >= 1_000_000
      "#{(value / 1_000_000.0).round(1)}M"
    elsif value >= 1_000
      "#{(value / 1_000.0).round(1)}K"
    else
      value.to_i.to_s
    end
  end

  # Get models with all quota levels (low, medium, high)
  def available_models_with_levels
    account_quotas.includes(:quota_definition)
      .where.not(quota_level: ['unknown'])
      .group_by { |q| q.quota_definition.claude_model_name }
      .map do |model_name, quotas|
        # Get the lowest level for this model (bottleneck determines real capability)
        if quotas.any? { |q| q.quota_level == 'low' }
          actual_level = 'low'
        elsif quotas.any? { |q| q.quota_level == 'medium' }
          actual_level = 'medium'
        else
          actual_level = 'high'
        end
        
        # Extract display name from full model name
        # Examples:
        # "Claude 3.5 Sonnet V1" -> "3.5 Sonnet V1"
        # "Claude 3.7 Sonnet V1" -> "3.7 Sonnet V1"
        # "Claude 4 Sonnet V1" -> "4 Sonnet V1"
        parts = model_name.split(' ')
        
        # Remove "Claude" and keep version number + model + version
        if parts.length >= 3 && parts[0] == 'Claude'
          if parts.last =~ /^V\d+$/
            # Has version: "Claude 3.5 Sonnet V1" -> "3.5 Sonnet V1"
            display_name = parts[1..-1].join(' ')
          else
            # No version: "Claude 3.5 Sonnet" -> "3.5 Sonnet"
            display_name = parts[1..-1].join(' ')
          end
        else
          # Fallback for unexpected format
          display_name = model_name
        end
        
        {
          name: display_name,
          level: actual_level
        }
      end
      .sort_by { |m| m[:name] }
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