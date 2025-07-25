# frozen_string_literal: true

class Admin < ApplicationRecord
  # Include concerns
  include Auditable
  
  # Include default devise modules if needed later
  has_secure_password

  # Enums
  enum role: {
    operator: 0,
    manager: 1,
    super_admin: 2
  }

  enum status: {
    active: 0,
    inactive: 1,
    suspended: 2
  }

  # Associations
  has_many :audit_logs, dependent: :nullify

  # Validations
  validates :username, presence: true, uniqueness: { case_sensitive: false }, 
            length: { minimum: 3, maximum: 50 },
            format: { with: /\A[a-zA-Z0-9_]+\z/, message: "只能包含字母、数字和下划线" }
  
  validates :email, presence: true, uniqueness: { case_sensitive: false },
            format: { with: URI::MailTo::EMAIL_REGEXP },
            length: { maximum: 100 }
  
  validates :password, length: { minimum: 8, maximum: 128 }, 
            format: { 
              with: /\A(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]/,
              message: "必须包含大小写字母、数字和特殊字符"
            }, 
            if: :password_required?
  
  validates :full_name, length: { maximum: 100 }, allow_blank: true
  validates :failed_login_attempts, numericality: { greater_than_or_equal_to: 0 }

  # Callbacks
  before_save :downcase_email

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :locked, -> { where('locked_until > ?', Time.current) }
  scope :unlocked, -> { where('locked_until IS NULL OR locked_until <= ?', Time.current) }

  # Constants
  MAX_LOGIN_ATTEMPTS = 5
  LOCK_DURATION = 30.minutes

  # Instance Methods
  def locked?
    locked_until.present? && locked_until > Time.current
  end

  def lock_account!
    update!(
      locked_until: Time.current + LOCK_DURATION,
      failed_login_attempts: MAX_LOGIN_ATTEMPTS
    )
  end

  def unlock_account!
    update!(
      locked_until: nil,
      failed_login_attempts: 0
    )
  end

  def increment_failed_login_attempts!
    increment!(:failed_login_attempts)
    lock_account! if failed_login_attempts >= MAX_LOGIN_ATTEMPTS
  end

  def reset_failed_login_attempts!
    update!(failed_login_attempts: 0)
  end

  def authenticate_with_lock_check(password)
    return false if locked?
    
    if authenticate(password)
      reset_failed_login_attempts!
      update!(last_login_at: Time.current)
      true
    else
      increment_failed_login_attempts!
      false
    end
  end

  def update_last_login!(ip_address)
    update!(
      last_login_at: Time.current,
      last_login_ip: ip_address
    )
  end

  def display_name
    full_name.presence || username
  end

  def can_manage_accounts?
    super_admin? || manager?
  end

  def can_manage_admins?
    super_admin?
  end

  def password_expired?
    return true if password_changed_at.nil?
    password_changed_at < 90.days.ago
  end

  def force_password_change!
    update!(password_changed_at: 1.year.ago)
  end

  private

  def downcase_email
    self.email = email.downcase if email.present?
  end

  def password_required?
    new_record? || password.present?
  end
  
  # Auditable configuration
  auditable_fields :username, :email, :full_name, :role, :status, :failed_login_attempts, :locked_until
  
  def audit_metadata
    {
      admin_role: role,
      account_status: status,
      login_attempts: failed_login_attempts,
      locked: locked?
    }
  end
end