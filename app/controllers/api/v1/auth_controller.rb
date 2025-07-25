# frozen_string_literal: true

class Api::V1::AuthController < Api::V1::BaseController
  before_action :authenticate_admin!, except: [:login, :refresh]
  before_action :extract_refresh_token, only: [:refresh]
  
  # POST /api/v1/auth/login
  def login
    @admin = Admin.find_by(username: login_params[:username])
    
    if @admin&.authenticate_with_lock_check(login_params[:password])
      # Log successful login
      log_login_attempt(true)
      
      # Generate tokens
      tokens = JwtService.generate_tokens(@admin)
      
      # Update last login info
      @admin.update_last_login!(request.remote_ip)
      
      render json: {
        success: true,
        message: '登录成功',
        data: {
          admin: admin_data(@admin),
          **tokens
        }
      }
    else
      # Log failed login
      log_login_attempt(false)
      
      error_message = if @admin&.locked?
        "账号已被锁定，请在 #{time_until_unlock(@admin)} 后重试"
      else
        '用户名或密码错误'
      end
      
      render json: {
        success: false,
        message: error_message
      }, status: :unauthorized
    end
  rescue => e
    Rails.logger.error "Login error: #{e.message}"
    render json: {
      success: false,
      message: '登录失败，请稍后重试'
    }, status: :internal_server_error
  end
  
  # POST /api/v1/auth/logout
  def logout
    # Revoke current token
    if current_token_payload
      jti = current_token_payload['jti']
      JwtService.revoke_token(jti) if jti
    end
    
    # Log logout
    AuditLog.log_action('logout', {
      admin: current_admin,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    })
    
    render json: {
      success: true,
      message: '已成功退出登录'
    }
  rescue => e
    Rails.logger.error "Logout error: #{e.message}"
    render json: {
      success: false,
      message: '退出登录失败'
    }, status: :internal_server_error
  end
  
  # POST /api/v1/auth/refresh
  def refresh
    result = JwtService.refresh_access_token(@refresh_token)
    
    if result
      render json: {
        success: true,
        message: 'Token刷新成功',
        data: result
      }
    else
      render json: {
        success: false,
        message: 'Token刷新失败，请重新登录'
      }, status: :unauthorized
    end
  rescue => e
    Rails.logger.error "Token refresh error: #{e.message}"
    render json: {
      success: false,
      message: 'Token刷新失败'
    }, status: :internal_server_error
  end
  
  # GET /api/v1/auth/me
  def me
    render json: {
      success: true,
      data: {
        admin: admin_data(current_admin),
        token_info: token_info
      }
    }
  rescue => e
    Rails.logger.error "Get current admin error: #{e.message}"
    render json: {
      success: false,
      message: '获取用户信息失败'
    }, status: :internal_server_error
  end
  
  # PUT /api/v1/auth/password
  def change_password
    if current_admin.authenticate(password_params[:current_password])
      if current_admin.update(password: password_params[:new_password])
        # Log password change
        AuditLog.log_action('password_change', {
          admin: current_admin,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        })
        
        render json: {
          success: true,
          message: '密码修改成功'
        }
      else
        render json: {
          success: false,
          message: '密码修改失败',
          errors: current_admin.errors.full_messages
        }, status: :unprocessable_entity
      end
    else
      render json: {
        success: false,
        message: '当前密码不正确'
      }, status: :unauthorized
    end
  rescue => e
    Rails.logger.error "Change password error: #{e.message}"
    render json: {
      success: false,
      message: '密码修改失败'
    }, status: :internal_server_error
  end
  
  # POST /api/v1/auth/check_token
  def check_token
    token_info = JwtService.token_info(extract_token)
    
    if token_info
      render json: {
        success: true,
        data: {
          valid: !token_info[:expired],
          token_info: token_info
        }
      }
    else
      render json: {
        success: false,
        message: 'Token无效'
      }, status: :unauthorized
    end
  rescue => e
    Rails.logger.error "Check token error: #{e.message}"
    render json: {
      success: false,
      message: 'Token检查失败'
    }, status: :internal_server_error
  end
  
  private
  
  def login_params
    params.require(:auth).permit(:username, :password)
  end
  
  def password_params
    params.require(:auth).permit(:current_password, :new_password)
  end
  
  def admin_data(admin)
    {
      id: admin.id,
      username: admin.username,
      email: admin.email,
      full_name: admin.full_name,
      role: admin.role,
      status: admin.status,
      last_login_at: admin.last_login_at,
      last_login_ip: admin.last_login_ip,
      permissions: {
        can_manage_accounts: admin.can_manage_accounts?,
        can_manage_admins: admin.can_manage_admins?
      }
    }
  end
  
  def token_info
    return nil unless current_token_payload
    
    {
      expires_at: Time.at(current_token_payload['exp']),
      issued_at: Time.at(current_token_payload['iat']),
      remaining_time: JwtService.token_remaining_time(current_token_payload),
      needs_refresh: JwtService.token_needs_refresh?(current_token_payload)
    }
  end
  
  def extract_refresh_token
    @refresh_token = params[:refresh_token]
    
    unless @refresh_token
      render json: {
        success: false,
        message: '缺少refresh_token参数'
      }, status: :bad_request
    end
  end
  
  def log_login_attempt(successful)
    AuditLog.log_login(
      @admin,
      request.remote_ip,
      request.user_agent,
      successful
    )
  end
  
  def time_until_unlock(admin)
    return '' unless admin.locked?
    
    remaining_seconds = (admin.locked_until - Time.current).to_i
    if remaining_seconds > 60
      "#{remaining_seconds / 60}分钟"
    else
      "#{remaining_seconds}秒"
    end
  end
end