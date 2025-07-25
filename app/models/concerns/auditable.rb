# frozen_string_literal: true

module Auditable
  extend ActiveSupport::Concern
  
  included do
    has_many :audit_logs, as: :target, dependent: :destroy
    
    # Callbacks for automatic auditing
    after_create :audit_create, if: :should_audit?
    after_update :audit_update, if: :should_audit?
    before_destroy :audit_destroy, if: :should_audit?
  end
  
  class_methods do
    def auditable_fields(*fields)
      @auditable_fields = fields
    end
    
    def get_auditable_fields
      @auditable_fields || []
    end
    
    def skip_audit_for(*actions)
      @skip_audit_actions = actions
    end
    
    def get_skip_audit_actions
      @skip_audit_actions || []
    end
  end
  
  private
  
  def should_audit?
    # Skip if explicitly disabled
    return false if @skip_audit
    
    # Skip if current thread has audit disabled
    return false if Thread.current[:skip_audit]
    
    true
  end
  
  def audit_create
    create_audit_record('create', audit_changes_for_create)
  end
  
  def audit_update
    return unless saved_changes.except('updated_at').any?
    
    # Filter changes to only include auditable fields if specified
    filtered_changes = filter_auditable_changes(saved_changes)
    return if filtered_changes.empty?
    
    create_audit_record('update', filtered_changes)
  end
  
  def audit_destroy
    create_audit_record('delete', audit_changes_for_destroy)
  end
  
  def audit_changes_for_create
    auditable_fields = self.class.get_auditable_fields
    if auditable_fields.any?
      attributes.slice(*auditable_fields.map(&:to_s))
    else
      attributes.except('created_at', 'updated_at', 'password_digest')
    end
  end
  
  def audit_changes_for_destroy
    auditable_fields = self.class.get_auditable_fields
    if auditable_fields.any?
      attributes.slice(*auditable_fields.map(&:to_s))
    else
      { id: id, deleted_at: Time.current }
    end
  end
  
  def filter_auditable_changes(changes)
    auditable_fields = self.class.get_auditable_fields
    
    if auditable_fields.any?
      # Only include specified fields
      changes.slice(*auditable_fields.map(&:to_s))
    else
      # Exclude sensitive and system fields
      excluded_fields = %w[updated_at password_digest created_at]
      changes.except(*excluded_fields)
    end
  end
  
  def create_audit_record(action, changes_data)
    # Skip if action is in skip list
    skip_actions = self.class.get_skip_audit_actions
    return if skip_actions.include?(action.to_sym)
    
    # Get current admin from thread local or controller
    current_admin = Thread.current[:current_admin] || 
                   (defined?(Current) && Current.respond_to?(:admin) ? Current.admin : nil)
    
    # Get request context if available
    request_context = Thread.current[:request_context] || {}
    
    AuditLog.create!(
      admin: current_admin,
      action: action,
      target: self,
      changes: changes_data,
      ip_address: request_context[:ip_address],
      user_agent: request_context[:user_agent],
      metadata: {
        model_class: self.class.name,
        performed_at: Time.current,
        request_id: request_context[:request_id]
      }.merge(audit_metadata)
    )
  rescue => e
    Rails.logger.error "Failed to create audit log for #{self.class.name}##{id}: #{e.message}"
  end
  
  def audit_metadata
    # Override in including models to add custom metadata
    {}
  end
  
  # Public methods for manual auditing
  def audit_action(action, changes = {}, metadata = {})
    current_admin = Thread.current[:current_admin]
    request_context = Thread.current[:request_context] || {}
    
    AuditLog.create!(
      admin: current_admin,
      action: action.to_s,
      target: self,
      changes: changes,
      ip_address: request_context[:ip_address],
      user_agent: request_context[:user_agent],
      metadata: {
        model_class: self.class.name,
        manual_audit: true,
        performed_at: Time.current
      }.merge(metadata)
    )
  end
  
  def skip_audit(&block)
    @skip_audit = true
    result = block.call
    @skip_audit = false
    result
  end
  
  def self.skip_audit(&block)
    Thread.current[:skip_audit] = true
    result = block.call
    Thread.current[:skip_audit] = false
    result
  end
end