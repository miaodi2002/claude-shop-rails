class ApplicationController < ActionController::Base
  # CSRF protection
  protect_from_forgery with: :exception
  
  # 设置当前上下文
  before_action :set_current_request_details
  
  # 异常处理
  rescue_from StandardError, with: :handle_standard_error
  rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
  rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing
  
  # 审计日志
  after_action :log_request, if: :should_log_request?
  
  protected
  
  def current_admin
    return @current_admin if defined?(@current_admin)
    
    @current_admin = nil
    
    token = request.headers['Authorization']&.sub(/^Bearer /, '') ||
            session[:admin_token]
    
    if token
      begin
        payload = JwtService.decode(token)
        @current_admin = Admin.find(payload['admin_id'])
      rescue JWT::DecodeError, ActiveRecord::RecordNotFound
        @current_admin = nil
      end
    end
    
    @current_admin
  end
  
  def admin_signed_in?
    current_admin.present?
  end
  
  def require_admin_authentication!
    unless admin_signed_in?
      respond_to do |format|
        format.html { redirect_to admin_login_path, alert: '请先登录' }
        format.json { render json: { error: '未授权访问' }, status: :unauthorized }
      end
    end
  end
  
  def set_current_request_details
    Current.admin = current_admin
    Current.request_id = request.uuid
    Current.user_agent = request.user_agent
    Current.ip_address = request.remote_ip
  end
  
  def handle_standard_error(exception)
    Rails.logger.error "#{exception.class}: #{exception.message}"
    Rails.logger.error exception.backtrace.join("\n")
    
    respond_to do |format|
      format.html { 
        render 'errors/500', 
               status: :internal_server_error,
               locals: { exception: exception }
      }
      format.json { 
        render json: { 
          error: 'Internal server error',
          message: Rails.env.development? ? exception.message : '服务器内部错误'
        }, status: :internal_server_error 
      }
    end
  end
  
  def handle_not_found(exception)
    respond_to do |format|
      format.html { render 'errors/404', status: :not_found }
      format.json { render json: { error: 'Not found' }, status: :not_found }
    end
  end
  
  def handle_parameter_missing(exception)
    respond_to do |format|
      format.html { 
        redirect_back(fallback_location: root_path, alert: "缺少必要参数: #{exception.param}")
      }
      format.json { 
        render json: { 
          error: 'Parameter missing', 
          param: exception.param 
        }, status: :bad_request 
      }
    end
  end
  
  def pagination_params
    {
      page: params[:page] || 1,
      per_page: [params[:per_page].to_i, 50].min.positive? || 10
    }
  end
  
  def search_params
    params.permit(:q, :model, :status, :sort, :order)
  end
  
  def should_log_request?
    # 记录所有管理员操作和API请求
    admin_signed_in? || request.path.start_with?('/api/')
  end
  
  def log_request
    return unless should_log_request?
    
    AuditLoggerService.log_request(
      admin: current_admin,
      action: "#{controller_name}##{action_name}",
      path: request.path,
      method: request.method,
      params: request.filtered_parameters,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      response_status: response.status
    )
  end
  
  # 缓存辅助方法
  def cache_key_for(*args)
    ['claude_shop', Rails.env, *args].join('/')
  end
  
  # JSON响应辅助方法
  def render_success(data = nil, message = nil, status = :ok)
    response = { success: true }
    response[:data] = data if data
    response[:message] = message if message
    render json: response, status: status
  end
  
  def render_error(message, errors = nil, status = :unprocessable_entity)
    response = { success: false, message: message }
    response[:errors] = errors if errors
    render json: response, status: status
  end
  
  # Turbo Stream 辅助方法
  def turbo_stream_flash(type, message)
    render turbo_stream: turbo_stream.update('flash', 
      partial: 'shared/flash', 
      locals: { type: type, message: message }
    )
  end
end