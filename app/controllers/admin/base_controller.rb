# frozen_string_literal: true
require 'ostruct'

module Admin
  class BaseController < ApplicationController
    before_action :authenticate_admin!
    before_action :require_admin_role!
    before_action :set_admin_layout_data
    
    layout 'admin'
    
    private
    
    def authenticate_admin!
      # 临时跳过认证 - 仅用于开发测试
      # TODO: 集成JWT认证
      true
    end
    
    def require_admin_role!
      # 临时跳过权限检查 - 仅用于开发测试
      # TODO: 实现权限控制
      true
    end
    
    def current_admin
      # 临时返回实际管理员记录 - 仅用于开发测试
      # TODO: 集成JWT认证后修改为从token获取用户
      @current_admin ||= AdminUser.find_by(id: 1) || AdminUser.first
    end
    helper_method :current_admin
    
    def set_admin_layout_data
      @admin_nav_items = [
        { name: '仪表板', path: admin_dashboard_path, icon: 'dashboard' },
        { name: 'AWS账号', path: admin_aws_accounts_path, icon: 'cloud' },
        { name: '配额管理', path: admin_account_quotas_path, icon: 'chart' },
        { name: '审计日志', path: admin_audit_logs_path, icon: 'history' },
        { name: '系统设置', path: admin_dashboard_path, icon: 'settings' }
      ]
      
      @admin_user_menu = [
        { name: '个人资料', path: admin_dashboard_path, icon: 'person' },
        { name: '修改密码', path: admin_dashboard_path, icon: 'lock' },
        { name: '退出登录', path: admin_dashboard_path, icon: 'logout', method: :delete }
      ]
    end
  end
end