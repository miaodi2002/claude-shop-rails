# frozen_string_literal: true

class Api::V1::BaseController < ApplicationController
  # Skip CSRF protection for API endpoints
  protect_from_forgery with: :null_session
  
  # Before actions
  before_action :set_default_response_format
  before_action :authenticate_admin!
  before_action :set_audit_context
  after_action :clear_audit_context
  
  # Error handling
  rescue_from StandardError, with: :handle_standard_error
  rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :handle_validation_error
  rescue_from JWT::ExpiredSignature, with: :handle_token_expired
  rescue_from JWT::DecodeError, with: :handle_invalid_token
  
  protected
  
  # Authentication
  def authenticate_admin!
    unless current_admin
      render_unauthorized('请先登录')
    end
  end
  
  def current_admin
    @current_admin ||= authenticate_from_token
  end
  
  def current_token_payload
    @current_token_payload
  end
  
  def authenticate_from_token
    token = extract_token
    return nil unless token
    
    result = JwtService.decode_access_token(token)
    return nil unless result
    
    @current_token_payload = result[:payload]
    
    # Check if token is revoked
    jti = @current_token_payload['jti']
    if jti && JwtService.token_revoked?(jti)
      return nil
    end
    
    result[:admin]
  rescue => e
    Rails.logger.error "Token authentication error: #{e.message}"
    nil
  end
  
  def extract_token
    authorization_header = request.headers['Authorization']
    JwtService.extract_token_from_header(authorization_header)
  end
  
  # Authorization helpers
  def require_super_admin!
    unless current_admin&.super_admin?
      render_forbidden('需要超级管理员权限')
    end
  end
  
  def require_manager_or_above!
    unless current_admin&.can_manage_accounts?
      render_forbidden('需要管理员权限')
    end
  end
  
  # Response helpers
  def render_success(message = '操作成功', data = nil)
    response_data = {
      success: true,
      message: message
    }
    response_data[:data] = data if data
    
    render json: response_data
  end
  
  def render_error(message = '操作失败', status = :unprocessable_entity, errors = nil)
    response_data = {
      success: false,
      message: message
    }
    response_data[:errors] = errors if errors
    
    render json: response_data, status: status
  end
  
  def render_unauthorized(message = '未授权访问')
    render json: {
      success: false,
      message: message,
      error_code: 'UNAUTHORIZED'
    }, status: :unauthorized
  end
  
  def render_forbidden(message = '权限不足')
    render json: {
      success: false,
      message: message,
      error_code: 'FORBIDDEN'
    }, status: :forbidden
  end
  
  def render_not_found(message = '资源不存在')
    render json: {
      success: false,
      message: message,
      error_code: 'NOT_FOUND'
    }, status: :not_found
  end
  
  # Pagination helpers
  def paginate_collection(collection, per_page = 20)
    page = params[:page] || 1
    per_page = [params[:per_page].to_i, per_page].min if params[:per_page]
    
    paginated = collection.page(page).per(per_page)
    
    {
      data: paginated,
      pagination: {
        current_page: paginated.current_page,
        total_pages: paginated.total_pages,
        total_count: paginated.total_count,
        per_page: paginated.limit_value,
        has_next: paginated.next_page.present?,
        has_prev: paginated.prev_page.present?
      }
    }
  end
  
  private
  
  def set_default_response_format
    request.format = :json
  end
  
  def set_audit_context
    AuditContextService.set_context(admin: current_admin, request: request)
  end
  
  def clear_audit_context
    AuditContextService.clear_context
  end
  
  # Error handlers
  def handle_standard_error(exception)
    Rails.logger.error "API Error: #{exception.class} - #{exception.message}"
    Rails.logger.error exception.backtrace.join("\n")
    
    render json: {
      success: false,
      message: '服务器内部错误',
      error_code: 'INTERNAL_SERVER_ERROR'
    }, status: :internal_server_error
  end
  
  def handle_not_found(exception)
    render_not_found('请求的资源不存在')
  end
  
  def handle_validation_error(exception)
    render_error(
      '数据验证失败',
      :unprocessable_entity,
      exception.record.errors.full_messages
    )
  end
  
  def handle_token_expired(exception)
    render json: {
      success: false,
      message: 'Token已过期，请重新登录',
      error_code: 'TOKEN_EXPIRED'
    }, status: :unauthorized
  end
  
  def handle_invalid_token(exception)
    render json: {
      success: false,
      message: 'Token无效，请重新登录',
      error_code: 'INVALID_TOKEN'
    }, status: :unauthorized
  end
  
  # Audit logging
  def log_admin_action(action, target = nil, metadata = {})
    AuditLog.log_action(action, {
      admin: current_admin,
      target: target,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: metadata.merge({
        controller: controller_name,
        action: action_name,
        request_id: request.uuid
      })
    })
  rescue => e
    Rails.logger.error "Failed to log admin action: #{e.message}"
  end
end