# frozen_string_literal: true

module Admin
  class AdminUsersController < BaseController
    before_action :require_super_admin!, except: [:show]
    before_action :set_admin_user, only: [:show, :edit, :update, :destroy, :activate, :deactivate, :unlock]

    def index
      @admin_users = AdminUser.includes(:audit_logs)
                              .order(created_at: :desc)
                              .page(params[:page])
                              .per(20)
      
      # 统计信息
      @stats = {
        total: AdminUser.count,
        active: AdminUser.active.count,
        inactive: AdminUser.inactive.count,
        suspended: AdminUser.suspended.count,
        locked: AdminUser.where('locked_until > ?', Time.current).count
      }
    end

    def show
      # 只有super_admin或查看自己的资料
      unless current_admin.super_admin? || @admin_user == current_admin
        redirect_to admin_root_path, alert: '没有权限查看该用户信息'
        return
      end
      
      @recent_audit_logs = @admin_user.audit_logs
                                     .order(created_at: :desc)
                                     .limit(10)
    end

    def new
      @admin_user = AdminUser.new
    end

    def create
      @admin_user = AdminUser.new(admin_user_params)
      @admin_user.password_changed_at = Time.current
      
      if @admin_user.save
        redirect_to admin_admin_users_path, notice: '用户创建成功'
      else
        render :new
      end
    end

    def edit
    end

    def update
      # 不允许用户修改自己的角色和状态
      if @admin_user == current_admin
        params[:admin_user].delete(:role)
        params[:admin_user].delete(:status)
      end
      
      if @admin_user.update(admin_user_params)
        redirect_to admin_admin_user_path(@admin_user), notice: '用户信息更新成功'
      else
        render :edit
      end
    end

    def destroy
      if @admin_user == current_admin
        redirect_to admin_admin_users_path, alert: '不能删除自己的账号'
        return
      end
      
      if AdminUser.super_admin.count == 1 && @admin_user.super_admin?
        redirect_to admin_admin_users_path, alert: '不能删除最后一个超级管理员'
        return
      end
      
      @admin_user.destroy
      redirect_to admin_admin_users_path, notice: '用户删除成功'
    end

    def activate
      @admin_user.update!(status: 'active')
      redirect_to admin_admin_users_path, notice: '用户已激活'
    end

    def deactivate
      if @admin_user == current_admin
        redirect_to admin_admin_users_path, alert: '不能停用自己的账号'
        return
      end
      
      @admin_user.update!(status: 'inactive')
      redirect_to admin_admin_users_path, notice: '用户已停用'
    end

    def unlock
      @admin_user.unlock_account!
      redirect_to admin_admin_users_path, notice: '用户已解锁'
    end

    private

    def require_super_admin!
      unless current_admin&.super_admin?
        redirect_to admin_root_path, alert: '只有超级管理员可以管理用户'
      end
    end

    def set_admin_user
      @admin_user = AdminUser.find(params[:id])
    end

    def admin_user_params
      permitted = [:username, :email, :full_name, :role, :status]
      
      # 新用户创建时需要密码
      if action_name == 'create'
        permitted += [:password, :password_confirmation]
      end
      
      # 密码更新是可选的
      if params[:admin_user][:password].present?
        permitted += [:password, :password_confirmation]
      end
      
      params.require(:admin_user).permit(permitted)
    end
  end
end