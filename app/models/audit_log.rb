# frozen_string_literal: true

class AuditLog < ApplicationRecord
  # Associations
  belongs_to :admin, optional: true
  belongs_to :target, polymorphic: true, optional: true

  # Validations
  validates :action, presence: true, length: { maximum: 50 }
  validates :ip_address, length: { maximum: 45 }, allow_blank: true
  validates :user_agent, length: { maximum: 500 }, allow_blank: true

  # Callbacks
  before_create :set_defaults

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :by_admin, ->(admin) { where(admin: admin) }
  scope :by_action, ->(action) { where(action: action) }
  scope :by_target_type, ->(type) { where(target_type: type) }
  scope :successful, -> { where(successful: true) }
  scope :failed, -> { where(successful: false) }
  scope :today, -> { where('created_at >= ?', Date.current.beginning_of_day) }
  scope :this_week, -> { where('created_at >= ?', 1.week.ago) }
  scope :this_month, -> { where('created_at >= ?', 1.month.ago) }

  # Action types
  ACTIONS = %w[
    create update delete 
    login logout login_failed
    refresh_quota test_connection
    export import
    password_reset password_change
    account_locked account_unlocked
  ].freeze

  # Class methods
  def self.log_action(action, options = {})
    create!(
      action: action,
      admin: options[:admin],
      target: options[:target],
      target_type: options[:target_type] || options[:target]&.class&.name,
      target_id: options[:target_id] || options[:target]&.id,
      changes: options[:changes],
      metadata: options[:metadata],
      ip_address: options[:ip_address],
      user_agent: options[:user_agent],
      successful: options.fetch(:successful, true),
      error_message: options[:error_message]
    )
  end

  def self.log_login(admin, ip_address, user_agent, successful = true)
    log_action(
      successful ? 'login' : 'login_failed',
      admin: admin,
      ip_address: ip_address,
      user_agent: user_agent,
      successful: successful,
      metadata: { 
        timestamp: Time.current,
        admin_username: admin&.username 
      }
    )
  end

  def self.search(query)
    return all if query.blank?

    where(
      "action LIKE :q OR target_type LIKE :q OR ip_address LIKE :q OR error_message LIKE :q",
      q: "%#{query}%"
    ).or(
      joins(:admin).where("admins.username LIKE :q OR admins.email LIKE :q", q: "%#{query}%")
    )
  end

  def self.export_csv
    CSV.generate(headers: true) do |csv|
      csv << %w[ID 时间 管理员 操作 目标类型 目标ID IP地址 是否成功 错误信息]
      
      find_each do |log|
        csv << [
          log.id,
          log.created_at.strftime('%Y-%m-%d %H:%M:%S'),
          log.admin&.username,
          log.action,
          log.target_type,
          log.target_id,
          log.ip_address,
          log.successful? ? '是' : '否',
          log.error_message
        ]
      end
    end
  end

  # Instance methods
  def display_action
    I18n.t("audit_log.actions.#{action}", default: action.humanize)
  end

  def target_display_name
    return '' unless target_type.present?
    
    case target_type
    when 'Admin'
      target&.username || "Admin##{target_id}"
    when 'AwsAccount'
      target&.name || "AwsAccount##{target_id}"
    else
      "#{target_type}##{target_id}"
    end
  end

  def changes_summary
    return '' unless changes.present?
    
    changes.map do |key, value|
      if value.is_a?(Array) && value.length == 2
        "#{key}: #{value[0]} → #{value[1]}"
      else
        "#{key}: #{value}"
      end
    end.join(', ')
  end

  private

  def set_defaults
    self.successful = true if successful.nil?
    self.metadata ||= {}
  end
end