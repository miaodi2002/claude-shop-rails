# frozen_string_literal: true

class SystemConfig < ApplicationRecord
  # Validations
  validates :key, presence: true, uniqueness: true, length: { maximum: 100 }
  validates :data_type, presence: true, 
            inclusion: { in: %w[string integer boolean json float] }
  validates :description, length: { maximum: 500 }, allow_blank: true

  # Callbacks
  before_save :validate_value_format
  after_update :clear_cache

  # Scopes
  scope :editable, -> { where(editable: true) }
  scope :encrypted, -> { where(encrypted: true) }
  scope :by_category, ->(category) { where("key LIKE ?", "#{category}.%") }

  # Cache
  def self.cache_key
    'system_configs/all'
  end

  # Class methods
  def self.get(key, default = nil)
    config = find_by(key: key)
    return default unless config
    config.typed_value
  rescue => e
    Rails.logger.error "Failed to get system config #{key}: #{e.message}"
    default
  end

  def self.set(key, value, options = {})
    config = find_or_initialize_by(key: key)
    config.value = value
    config.data_type = options[:data_type] || detect_data_type(value)
    config.description = options[:description] if options[:description]
    config.editable = options.fetch(:editable, true)
    config.encrypted = options.fetch(:encrypted, false)
    config.save!
    config
  end

  def self.bulk_update(configs)
    transaction do
      configs.each do |key, value|
        config = find_by(key: key)
        next unless config&.editable?
        config.update!(value: value)
      end
    end
  end

  def self.export
    all.each_with_object({}) do |config, hash|
      hash[config.key] = {
        value: config.typed_value,
        data_type: config.data_type,
        description: config.description,
        editable: config.editable,
        encrypted: config.encrypted
      }
    end
  end

  def self.import(data)
    transaction do
      data.each do |key, attributes|
        set(key, attributes[:value], attributes.except(:value))
      end
    end
  end

  # Predefined configuration keys
  def self.define_defaults
    {
      # System settings
      'system.maintenance_mode' => { value: false, data_type: 'boolean', description: '系统维护模式' },
      'system.allow_registration' => { value: false, data_type: 'boolean', description: '允许新用户注册' },
      
      # AWS settings
      'aws.default_region' => { value: 'us-east-1', data_type: 'string', description: 'AWS默认区域' },
      'aws.quota_refresh_interval' => { value: 3600, data_type: 'integer', description: '配额刷新间隔（秒）' },
      'aws.connection_timeout' => { value: 30, data_type: 'integer', description: 'AWS连接超时时间（秒）' },
      
      # Security settings
      'security.session_timeout' => { value: 86400, data_type: 'integer', description: '会话超时时间（秒）' },
      'security.max_login_attempts' => { value: 5, data_type: 'integer', description: '最大登录尝试次数' },
      'security.lock_duration' => { value: 1800, data_type: 'integer', description: '账号锁定时长（秒）' },
      
      # Display settings
      'display.items_per_page' => { value: 20, data_type: 'integer', description: '每页显示条目数' },
      'display.show_sold_out' => { value: false, data_type: 'boolean', description: '显示已售罄账号' },
      
      # Notification settings
      'notification.telegram_enabled' => { value: false, data_type: 'boolean', description: '启用Telegram通知' },
      'notification.low_quota_threshold' => { value: 10, data_type: 'integer', description: '低配额警告阈值（%）' }
    }
  end

  def self.setup_defaults
    define_defaults.each do |key, options|
      next if exists?(key: key)
      set(key, options[:value], options)
    end
  end

  # Instance methods
  def typed_value
    case data_type
    when 'integer'
      value.to_i
    when 'float'
      value.to_f
    when 'boolean'
      ActiveModel::Type::Boolean.new.cast(value)
    when 'json'
      JSON.parse(value)
    else
      value
    end
  rescue => e
    Rails.logger.error "Failed to parse config value for #{key}: #{e.message}"
    value
  end

  def typed_value=(val)
    self.value = case data_type
    when 'json'
      val.is_a?(String) ? val : val.to_json
    else
      val.to_s
    end
  end

  def display_value
    if encrypted?
      '••••••••'
    elsif data_type == 'boolean'
      typed_value ? '是' : '否'
    else
      typed_value.to_s
    end
  end

  private

  def self.detect_data_type(value)
    case value
    when TrueClass, FalseClass
      'boolean'
    when Integer
      'integer'
    when Float
      'float'
    when Hash, Array
      'json'
    else
      'string'
    end
  end

  def validate_value_format
    case data_type
    when 'integer'
      Integer(value)
    when 'float'
      Float(value)
    when 'boolean'
      %w[true false 1 0 yes no].include?(value.to_s.downcase)
    when 'json'
      JSON.parse(value) if value.present?
    end
  rescue => e
    errors.add(:value, "格式不正确: #{e.message}")
    throw :abort
  end

  def clear_cache
    Rails.cache.delete(self.class.cache_key)
  end
end