# frozen_string_literal: true

class QuotaDefinition < ApplicationRecord
  # Associations
  has_many :account_quotas, dependent: :destroy
  has_many :aws_accounts, through: :account_quotas
  
  
  # Validations
  validates :quota_code, presence: true, uniqueness: true
  validates :claude_model_name, :quota_type, :quota_name, presence: true
  
  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :by_model, ->(model_name) { where(claude_model_name: model_name) }
  scope :by_type, ->(quota_type) { where(quota_type: quota_type) }
  
  # Quota types
  QUOTA_TYPES = {
    'requests_per_minute' => 'Requests per minute',
    'tokens_per_minute' => 'Tokens per minute',
    'tokens_per_day' => 'Tokens per day'
  }.freeze
  
  # Instance methods
  def display_name
    "#{claude_model_name} - #{quota_type_display}"
  end
  
  # Alias for compatibility
  def model_name
    claude_model_name
  end
  
  def quota_type_display
    QUOTA_TYPES[quota_type] || quota_type.humanize
  end
  
  def format_value(value)
    return 'N/A' if value.nil?
    
    case quota_type
    when 'requests_per_minute'
      "#{value.to_i} RPM"
    when 'tokens_per_minute'
      "#{number_with_delimiter(value.to_i)} TPM"
    when 'tokens_per_day'
      "#{number_with_delimiter(value.to_i)} TPD"
    else
      value.to_s
    end
  end

  # Unit method for display compatibility
  def unit
    case quota_type
    when 'requests_per_minute'
      'RPM'
    when 'tokens_per_minute'
      'TPM'
    when 'tokens_per_day'
      'TPD'
    else
      ''
    end
  end

  # Service name for compatibility
  def service_name
    quota_name
  end

  # Additional compatibility methods
  # 注意：这个方法返回的是定义级别，不是实际配额级别
  # 实际配额级别应该通过AccountQuota.calculate_level计算
  def definition_quota_level
    return 'unknown' unless default_value
    # 这里可以根据需要定义配额定义本身的级别分类
    # 但通常不需要，建议使用AccountQuota的级别判断
    'medium' # 默认值被视为中配额基准
  end

  def is_adjustable?
    true # Most AWS quotas are adjustable
  end
  
  private
  
  def number_with_delimiter(number)
    number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end
end