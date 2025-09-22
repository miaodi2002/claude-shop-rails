# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    before_action :authenticate_admin!
    before_action :require_admin_role!
    before_action :set_admin_layout_data
    
    layout 'admin'
    
    private
    
    def authenticate_admin!
      unless current_admin
        redirect_to admin_login_path, alert: '请先登录'
      end
    end
    
    def require_admin_role!
      unless current_admin&.active?
        redirect_to admin_login_path, alert: '账号已被停用'
      end
    end
    
    def current_admin
      return nil unless session[:admin_id]
      
      @current_admin ||= AdminUser.active.find_by(id: session[:admin_id])
      
      # 检查会话是否过期 (24小时)
      if @current_admin && session_expired?
        session.clear
        @current_admin = nil
      end
      
      @current_admin
    end
    helper_method :current_admin
    
    def set_admin_layout_data
      @admin_nav_items = [
        { name: '仪表板', path: admin_dashboard_path, icon: 'dashboard' },
        { name: 'AWS账号', path: admin_aws_accounts_path, icon: 'cloud' },
        { name: '配额管理', path: admin_account_quotas_path, icon: 'chart' },
        { name: '费用管理', path: admin_costs_path, icon: 'dollar-sign' },
        { name: '审计日志', path: admin_audit_logs_path, icon: 'history' },
        { name: '后台任务', path: '/sidekiq', icon: 'settings', target: '_blank' }
      ]
      
      # 只有超级管理员可以看到用户管理
      if current_admin&.super_admin?
        @admin_nav_items << { name: '用户管理', path: admin_admin_users_path, icon: 'users' }
      end
      
      @admin_user_menu = [
        { name: '个人资料', path: admin_dashboard_path, icon: 'person' },
        { name: '修改密码', path: admin_dashboard_path, icon: 'lock' },
        { name: '退出登录', path: admin_logout_path, icon: 'logout', method: :delete }
      ]
    end
    
    def session_expired?
      return true unless session[:admin_logged_in_at]
      
      logged_in_time = Time.at(session[:admin_logged_in_at])
      logged_in_time < 24.hours.ago
    end
  end
end