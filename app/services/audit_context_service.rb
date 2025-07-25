# frozen_string_literal: true

class AuditContextService
  class << self
    # Set audit context for the current thread
    def set_context(admin: nil, request: nil)
      Thread.current[:current_admin] = admin
      
      if request
        Thread.current[:request_context] = {
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          request_id: request.uuid || SecureRandom.uuid,
          method: request.method,
          path: request.path,
          params: filtered_params(request.params)
        }
      end
    end
    
    # Clear audit context
    def clear_context
      Thread.current[:current_admin] = nil
      Thread.current[:request_context] = nil
    end
    
    # Execute block with audit context
    def with_context(admin: nil, request: nil, &block)
      old_admin = Thread.current[:current_admin]
      old_context = Thread.current[:request_context]
      
      set_context(admin: admin, request: request)
      result = block.call
      
      Thread.current[:current_admin] = old_admin
      Thread.current[:request_context] = old_context
      
      result
    end
    
    # Get current audit context
    def current_admin
      Thread.current[:current_admin]
    end
    
    def current_request_context
      Thread.current[:request_context] || {}
    end
    
    # Manual audit logging
    def log_action(action, target: nil, admin: nil, changes: {}, metadata: {}, request: nil)
      admin ||= current_admin
      request_context = request ? extract_request_context(request) : current_request_context
      
      AuditLog.create!(
        admin: admin,
        action: action.to_s,
        target: target,
        changes: changes,
        ip_address: request_context[:ip_address],
        user_agent: request_context[:user_agent],
        metadata: {
          performed_at: Time.current,
          manual_log: true,
          request_id: request_context[:request_id]
        }.merge(metadata)
      )
    rescue => e
      Rails.logger.error "Failed to create manual audit log: #{e.message}"
      false
    end
    
    # Batch audit logging for multiple actions
    def log_batch_actions(actions, admin: nil, request: nil)
      admin ||= current_admin
      request_context = request ? extract_request_context(request) : current_request_context
      
      audit_logs = actions.map do |action_data|
        {
          admin: admin,
          action: action_data[:action].to_s,
          target: action_data[:target],
          target_type: action_data[:target]&.class&.name,
          target_id: action_data[:target]&.id,
          changes: action_data[:changes] || {},
          ip_address: request_context[:ip_address],
          user_agent: request_context[:user_agent],
          metadata: {
            performed_at: Time.current,
            batch_log: true,
            request_id: request_context[:request_id]
          }.merge(action_data[:metadata] || {}),
          created_at: Time.current,
          updated_at: Time.current
        }
      end
      
      AuditLog.insert_all(audit_logs)
    rescue => e
      Rails.logger.error "Failed to create batch audit logs: #{e.message}"
      false
    end
    
    # Security event logging
    def log_security_event(event_type, details = {}, admin: nil, request: nil)
      log_action(
        "security_#{event_type}",
        admin: admin,
        request: request,
        metadata: {
          security_event: true,
          event_type: event_type,
          severity: details[:severity] || 'medium',
          details: details
        }
      )
    end
    
    # Performance event logging
    def log_performance_event(event_type, metrics = {}, admin: nil, request: nil)
      log_action(
        "performance_#{event_type}",
        admin: admin,
        request: request,
        metadata: {
          performance_event: true,
          event_type: event_type,
          metrics: metrics,
          timestamp: Time.current
        }
      )
    end
    
    # System event logging
    def log_system_event(event_type, details = {}, admin: nil)
      log_action(
        "system_#{event_type}",
        admin: admin,
        metadata: {
          system_event: true,
          event_type: event_type,
          details: details,
          hostname: Socket.gethostname,
          process_id: Process.pid
        }
      )
    end
    
    private
    
    def extract_request_context(request)
      {
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        request_id: request.uuid || SecureRandom.uuid,
        method: request.method,
        path: request.path
      }
    end
    
    def filtered_params(params)
      # Filter out sensitive parameters
      filtered = params.except('password', 'password_confirmation', 'secret_key', 'token')
      
      # Limit size to prevent log bloat
      filtered.to_s.truncate(1000)
    rescue
      '[filtered]'
    end
  end
end