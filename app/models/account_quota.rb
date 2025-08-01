# frozen_string_literal: true

class AccountQuota < ApplicationRecord
  self.table_name = 'account_quotas'
  
  # Associations
  belongs_to :aws_account
  belongs_to :quota_definition
  
  # Validations
  validates :current_quota, numericality: { greater_than_or_equal_to: 0 }
  validates :aws_account_id, uniqueness: { scope: :quota_definition_id }
  
  # Enums
  enum :sync_status, { 
    pending: 'pending', 
    success: 'success', 
    failed: 'failed' 
  }, default: 'pending'
  
  enum :quota_level, { 
    unknown: 'unknown', 
    low: 'low',
    medium: 'medium',
    high: 'high' 
  }, default: 'unknown'
  
  # Scopes
  scope :by_model, ->(model_name) { 
    joins(:quota_definition).where(quota_definitions: { claude_model_name: model_name }) 
  }
  scope :by_type, ->(quota_type) { 
    joins(:quota_definition).where(quota_definitions: { quota_type: quota_type }) 
  }
  scope :high_level, -> { where(quota_level: 'high') }
  scope :medium_level, -> { where(quota_level: 'medium') }
  scope :low_level, -> { where(quota_level: 'low') }
  scope :recently_synced, -> { where('last_sync_at > ?', 24.hours.ago) }
  scope :sync_failed, -> { where(sync_status: 'failed') }
  scope :needs_sync, -> { where('last_sync_at IS NULL OR last_sync_at < ?', 24.hours.ago) }
  
  # Delegations
  delegate :model_name, :quota_type, :quota_name, :display_name, 
           :quota_code, :format_value, to: :quota_definition
  
  # Instance methods
  def refresh!
    Rails.logger.info "Refreshing quota: #{quota_definition.display_name} for account #{aws_account.name}"
    
    result = AwsQuotaService.fetch_single_quota(
      aws_account, 
      quota_definition.quota_code
    )
    
    if result[:success]
      new_level = calculate_level(result[:value])
      
      update!(
        current_quota: result[:value],
        quota_level: new_level,
        is_adjustable: result[:adjustable],
        last_sync_at: Time.current,
        sync_status: 'success',
        sync_error: nil
      )
      
      Rails.logger.info "Successfully refreshed quota: #{formatted_current_value}"
      true
    else
      update!(
        sync_status: 'failed',
        sync_error: result[:error],
        last_sync_at: Time.current
      )
      
      Rails.logger.error "Failed to refresh quota: #{result[:error]}"
      false
    end
  rescue => e
    Rails.logger.error "Error refreshing quota: #{e.message}"
    update!(
      sync_status: 'failed',
      sync_error: e.message,
      last_sync_at: Time.current
    )
    false
  end
  
  def formatted_current_value
    quota_definition.format_value(current_quota)
  end
  
  def formatted_default_value
    quota_definition.format_value(quota_definition.default_value)
  end
  
  def level_color
    case quota_level
    when 'high' then 'green'
    when 'medium' then 'blue'
    when 'low' then 'red'
    else 'gray'
    end
  end
  
  def level_icon
    case quota_level
    when 'high' then '✅'
    when 'medium' then '🟡'
    when 'low' then '⚠️'
    else '❓'
    end
  end
  
  def display_sync_status
    case sync_status
    when 'success'
      last_sync_at? ? "成功 (#{I18n.l(last_sync_at, format: :short)})" : "成功"
    when 'failed'
      "失败: #{sync_error}"
    when 'pending'
      "等待同步"
    end
  end

  def display_quota_level
    case quota_level
    when 'high'
      '高配额'
    when 'medium'
      '标准配额'
    when 'low'
      '低配额'
    else
      '未知'
    end
  end

  def sync_status_display
    display_sync_status
  end

  def has_high_quota?
    quota_level == 'high'
  end

  def has_medium_quota?
    quota_level == 'medium'
  end

  def has_low_quota?
    quota_level == 'low'
  end

  def sync_success?
    sync_status == 'success'
  end

  def needs_refresh?
    last_sync_at.nil? || last_sync_at < 24.hours.ago
  end
  
  private
  
  def calculate_level(current_value)
    return 'unknown' if current_value.nil?
    
    default_val = quota_definition.default_value
    return 'unknown' if default_val.nil?
    
    # 三级判断逻辑：低于默认值为低配额，等于默认值为中配额，高于默认值为高配额
    if current_value < default_val
      'low'
    elsif current_value == default_val
      'medium'
    else
      'high'
    end
  end
end