# frozen_string_literal: true

module Admin
  class SessionsController < ApplicationController
    before_action :redirect_if_authenticated, only: [:new, :create]
    
    layout 'admin_login'

    def new
      # 显示登录表单
    end

    def create
      @admin = AdminUser.find_by(email: params[:email]&.downcase)
      
      if @admin && @admin.authenticate_with_lock_check(params[:password])
        create_session(@admin)
        redirect_to admin_root_path, notice: '登录成功'
      else
        handle_login_failure
      end
    end

    def destroy
      if current_admin
        # 记录登出日志
        AuditContextService.set_context(
          admin: current_admin,
          request: request
        )
        
        Rails.logger.info "Admin logout: #{current_admin.email}"
      end
      
      session.clear
      redirect_to admin_login_path, notice: '已退出登录'
    end

    private

    def create_session(admin)
      session[:admin_id] = admin.id
      session[:admin_logged_in_at] = Time.current.to_i
      
      # 更新最后登录信息
      admin.update_last_login!(request.remote_ip)
      
      # 设置审计上下文
      AuditContextService.set_context(
        admin: admin,
        request: request
      )
      
      Rails.logger.info "Admin login successful: #{admin.email} from #{request.remote_ip}"
    end

    def handle_login_failure
      if @admin
        if @admin.locked?
          flash.now[:alert] = "账号已被锁定，请#{time_ago_in_words(@admin.locked_until)}后重试"
        else
          remaining_attempts = AdminUser::MAX_LOGIN_ATTEMPTS - @admin.failed_login_attempts
          flash.now[:alert] = "邮箱或密码错误#{remaining_attempts > 0 ? "，还有#{remaining_attempts}次尝试机会" : ""}"
        end
      else
        flash.now[:alert] = '邮箱或密码错误'
      end
      
      Rails.logger.warn "Admin login failed: #{params[:email]} from #{request.remote_ip}"
      render :new
    end

    def redirect_if_authenticated
      if current_admin
        redirect_to admin_root_path
      end
    end

    def authenticate_admin!
      # Override parent method - sessions controller doesn't need authentication
    end
  end
end