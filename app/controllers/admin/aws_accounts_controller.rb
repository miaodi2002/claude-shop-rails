# frozen_string_literal: true

module Admin
  class AwsAccountsController < BaseController
    before_action :set_aws_account, only: [:show, :edit, :update, :destroy, :activate, :deactivate, :refresh_quota]
    
    def index
      @aws_accounts = filtered_accounts.order(:id).page(params[:page]).per(20) # removed :quotas include
      @total_accounts = AwsAccount.count
      @active_accounts = AwsAccount.active.count
      @total_quota_remaining = 0 # Quota.sum(:quota_remaining)
      
      respond_to do |format|
        format.html
        format.json { render json: aws_accounts_json }
      end
    end
    
    def show
      @quotas = @aws_account.quotas.includes(:quota_histories).order(:service_name)
      @recent_quota_histories = [] # @aws_account.quota_histories.recent.limit(10)
      @audit_logs = [] # @aws_account.audit_logs.recent.limit(5)
      
      # 获取该账号最近的刷新任务
      @recent_refresh_jobs = RefreshJob.for_account(@aws_account).recent.limit(5)
      @current_refresh_job = RefreshJob.for_account(@aws_account).in_progress.first
    end
    
    def new
      @aws_account = AwsAccount.new
    end
    
    def create
      @aws_account = AwsAccount.new(aws_account_params)
      
      if @aws_account.save
        # 记录审计日志
        audit_log('create', "创建AWS账号: #{@aws_account.name}")
        
        # 异步获取配额信息
        RefreshQuotaJob.perform_later(@aws_account.id) if @aws_account.active?
        
        redirect_to admin_aws_account_path(@aws_account), 
                    notice: "AWS账号 #{@aws_account.name} 创建成功"
      else
        render :new, status: :unprocessable_entity
      end
    end
    
    def edit
    end
    
    def update
      old_status = @aws_account.status
      
      if @aws_account.update(aws_account_params)
        # 记录审计日志
        changes = @aws_account.previous_changes.except('updated_at')
        audit_log('update', "更新AWS账号: #{changes.keys.join(', ')}")
        
        # 状态变更处理
        handle_status_change(old_status, @aws_account.status)
        
        redirect_to admin_aws_account_path(@aws_account), 
                    notice: "AWS账号 #{@aws_account.name} 更新成功"
      else
        render :edit, status: :unprocessable_entity
      end
    end
    
    def destroy
      account_name = @aws_account.name
      
      if @aws_account.destroy
        audit_log('delete', "删除AWS账号: #{account_name}")
        redirect_to admin_aws_accounts_path, notice: "AWS账号 #{account_name} 删除成功"
      else
        redirect_to admin_aws_account_path(@aws_account), 
                    alert: "删除失败: #{@aws_account.errors.full_messages.join(', ')}"
      end
    end
    
    # 激活账号
    def activate
      if @aws_account.update(status: :active)
        RefreshQuotaJob.perform_later(@aws_account.id)
        audit_log('activate', "激活AWS账号: #{@aws_account.name}")
        redirect_to admin_aws_account_path(@aws_account), notice: '账号已激活'
      else
        redirect_to admin_aws_account_path(@aws_account), alert: '激活失败'
      end
    end
    
    # 停用账号
    def deactivate
      if @aws_account.update(status: :inactive)
        audit_log('deactivate', "停用AWS账号: #{@aws_account.name}")
        redirect_to admin_aws_account_path(@aws_account), notice: '账号已停用'
      else
        redirect_to admin_aws_account_path(@aws_account), alert: '停用失败'
      end
    end
    
    # 刷新配额
    def refresh_quota
      RefreshQuotaJob.perform_later(@aws_account.id, { job_type: :manual })
      audit_log('refresh_quota', "手动刷新配额: #{@aws_account.name}")
      redirect_to admin_aws_account_path(@aws_account), notice: '配额刷新任务已启动，刷新页面查看进度'
    end
    
    # 批量刷新
    def bulk_refresh
      account_ids = params[:account_ids]&.reject(&:blank?)
      
      if account_ids.blank?
        redirect_to admin_aws_accounts_path, alert: '请选择要刷新的账号'
        return
      end
      
      accounts = AwsAccount.where(id: account_ids, status: :active)
      
      if accounts.any?
        # 创建批量刷新任务
        job = RefreshJob.create!(
          job_type: 'bulk_refresh',
          status: 'pending',
          total_accounts: accounts.count,
          account_ids: account_ids
        )
        
        # 异步执行批量刷新
        BulkRefreshJob.perform_later(job.id)
        
        audit_log('bulk_refresh', "批量刷新 #{accounts.count} 个账号")
        redirect_to admin_aws_accounts_path, notice: "已启动 #{accounts.count} 个账号的批量刷新"
      else
        redirect_to admin_aws_accounts_path, alert: '没有找到有效的活跃账号'
      end
    end
    
    # 导出数据
    def export
      accounts = filtered_accounts.includes(:quotas)
      
      respond_to do |format|
        format.csv do
          csv_data = generate_csv(accounts)
          send_data csv_data, 
                    filename: "aws_accounts_#{Date.current.strftime('%Y%m%d')}.csv",
                    type: 'text/csv'
        end
        format.json do
          render json: {
            accounts: accounts.as_json(include: :quotas),
            exported_at: Time.current,
            total_count: accounts.count
          }
        end
      end
    end
    
    private
    
    def set_aws_account
      @aws_account = AwsAccount.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_aws_accounts_path, alert: '账号不存在'
    end
    
    def aws_account_params
      params.require(:aws_account).permit(
        :name, :account_id, :access_key, :secret_key, 
        :region, :status, :description, :tags
      )
    end
    
    def filtered_accounts
      scope = AwsAccount.all
      
      # 搜索过滤
      if params[:search].present?
        search_term = "%#{params[:search]}%"
        scope = scope.where(
          "name LIKE ? OR account_id LIKE ? OR description LIKE ?",
          search_term, search_term, search_term
        )
      end
      
      # 状态过滤
      if params[:status].present? && params[:status] != 'all'
        scope = scope.where(status: params[:status])
      end
      
      # 区域过滤
      if params[:region].present? && params[:region] != 'all'
        scope = scope.where(region: params[:region])
      end
      
      # 配额过滤
      case params[:quota_filter]
      when 'available'
        scope = scope.joins(:quotas).where('quotas.quota_remaining > 0')
      when 'exhausted'
        scope = scope.joins(:quotas).where('quotas.quota_remaining <= 0')
      when 'no_quota'
        scope = scope.left_joins(:quotas).where(quotas: { id: nil })
      end
      
      scope
    end
    
    def aws_accounts_json
      {
        accounts: @aws_accounts.map do |account|
          account.as_json(
            include: {
              quotas: { only: [:service_code, :quota_remaining, :quota_used] }
            },
            methods: [:display_status, :total_quota_remaining]
          )
        end,
        pagination: {
          page: @aws_accounts.current_page,
          pages: @aws_accounts.total_pages,
          count: @aws_accounts.total_count,
          per_page: @aws_accounts.limit_value
        },
        summary: {
          total_accounts: @total_accounts,
          active_accounts: @active_accounts,
          total_quota_remaining: @total_quota_remaining
        }
      }
    end
    
    def handle_status_change(old_status, new_status)
      return if old_status == new_status
      
      case new_status
      when 'active'
        RefreshQuotaJob.perform_later(@aws_account.id) if old_status != 'active'
      when 'inactive'
        # 可以添加停用时的清理逻辑
      end
    end
    
    def generate_csv(accounts)
      require 'csv'
      
      CSV.generate(headers: true) do |csv|
        csv << [
          'ID', '账号名称', 'AWS账号ID', '区域', '状态', 
          '总配额', '剩余配额', '描述', '创建时间', '更新时间'
        ]
        
        accounts.each do |account|
          csv << [
            account.id,
            account.name,
            account.account_id,
            account.region,
            I18n.t("aws_account.status.#{account.status}"),
            account.quotas.sum(:quota_limit),
            account.quotas.sum(:quota_remaining),
            account.description,
            account.created_at.strftime('%Y-%m-%d %H:%M'),
            account.updated_at.strftime('%Y-%m-%d %H:%M')
          ]
        end
      end
    end
    
    def audit_log(action, details)
      AuditLog.log_action(action,
        admin: current_admin,
        target: @aws_account,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        successful: true,
        metadata: { details: details }
      )
    end
  end
end