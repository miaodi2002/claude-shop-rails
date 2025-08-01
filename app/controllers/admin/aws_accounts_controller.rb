# frozen_string_literal: true

module Admin
  class AwsAccountsController < BaseController
    before_action :set_aws_account, only: [:show, :edit, :update, :destroy, :activate, :deactivate, :refresh_quota]
    
    def index
      @aws_accounts = filtered_accounts.includes(:account_quotas).order(:id).page(params[:page]).per(20)
      @total_accounts = AwsAccount.count
      @active_accounts = AwsAccount.active.count
      @high_quota_count = AccountQuota.joins(:quota_definition)
                                     .where('current_quota > 0')
                                     .count
      
      respond_to do |format|
        format.html
        format.json { render json: aws_accounts_json }
      end
    end
    
    def show
      @account_quotas = @aws_account.account_quotas.includes(:quota_definition).order('quota_definitions.quota_name')
      @audit_logs = @aws_account.audit_logs.recent.limit(5)
      
      # 获取该账号最近的刷新任务
      @recent_refresh_jobs = RefreshJob.for_account(@aws_account).recent.limit(5)
      @current_refresh_job = RefreshJob.for_account(@aws_account).in_progress.first
      
      # 按模型分组配额数据，用于简化显示
      @quotas_by_model = group_quotas_by_model(@account_quotas)
      
      # 临时解决方案：使用最近同步的配额作为历史记录
      # TODO: 实现专门的配额历史追踪表
      @recent_quota_histories = @aws_account.account_quotas
                                          .includes(:quota_definition)
                                          .where.not(last_sync_at: nil)
                                          .order(last_sync_at: :desc)
                                          .limit(10)
    end
    
    def new
      @aws_account = AwsAccount.new
    end
    
    def create
      @aws_account = AwsAccount.new(aws_account_params)
      
      # 首先验证AWS凭证并获取账号ID
      account_info_result = AwsAccountInfoService.fetch_and_set_account_id(@aws_account)
      
      unless account_info_result[:success]
        @aws_account.errors.add(:access_key, account_info_result[:error])
        render :new, status: :unprocessable_entity
        return
      end
      
      if @aws_account.save
        # 记录审计日志
        audit_log('create', "创建AWS账号: #{@aws_account.name} (账号ID: #{@aws_account.account_id})")
        
        # 异步获取配额信息
        if @aws_account.active?
          RefreshQuotaJob.perform_later(@aws_account.id, { job_type: :manual })
          notice_message = "AWS账号 #{@aws_account.name} 创建成功，账号ID: #{@aws_account.account_id}。正在获取配额信息..."
        else
          notice_message = "AWS账号 #{@aws_account.name} 创建成功，账号ID: #{@aws_account.account_id}"
        end
        
        redirect_to admin_aws_account_path(@aws_account), notice: notice_message
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
      accounts = filtered_accounts.includes(:account_quotas)
      
      respond_to do |format|
        format.csv do
          csv_data = generate_csv(accounts)
          send_data csv_data, 
                    filename: "aws_accounts_#{Date.current.strftime('%Y%m%d')}.csv",
                    type: 'text/csv'
        end
        format.json do
          render json: {
            accounts: accounts.as_json(include: :account_quotas),
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
        :name, :access_key, :secret_key, 
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
        scope = scope.joins(:account_quotas).where('account_quotas.current_quota > 0')
      when 'exhausted'
        scope = scope.joins(:account_quotas).where('account_quotas.current_quota <= 0')
      when 'no_quota'
        scope = scope.left_joins(:account_quotas).where(account_quotas: { id: nil })
      end
      
      scope
    end
    
    def aws_accounts_json
      {
        accounts: @aws_accounts.map do |account|
          account.as_json(
            include: {
              account_quotas: { 
                include: :quota_definition,
                only: [:current_quota, :quota_limit, :last_sync_at] 
              }
            },
            methods: [:display_status, :masked_access_key]
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
          high_quota_count: @high_quota_count
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
          '活跃配额数量', '当前总配额', '描述', '创建时间', '更新时间'
        ]
        
        accounts.each do |account|
          active_quotas = account.account_quotas.where('current_quota > 0').count
          total_current_quota = account.account_quotas.sum(:current_quota)
          
          csv << [
            account.id,
            account.name,
            account.account_id,
            account.region,
            I18n.t("aws_account.status.#{account.status}"),
            active_quotas,
            total_current_quota,
            account.description,
            account.created_at.strftime('%Y-%m-%d %H:%M'),
            account.updated_at.strftime('%Y-%m-%d %H:%M')
          ]
        end
      end
    end
    
    def group_quotas_by_model(account_quotas)
      # 按模型名称分组配额数据
      grouped = account_quotas.group_by { |quota| quota.quota_definition.claude_model_name }
      
      # 为每个模型整理RPM、TPM、TPD数据
      result = {}
      grouped.each do |model_name, quotas|
        model_data = {
          name: model_name,
          rpm: nil,
          tpm: nil,
          tpd: nil
        }
        
        quotas.each do |quota|
          case quota.quota_definition.quota_type
          when 'requests_per_minute'
            model_data[:rpm] = quota
          when 'tokens_per_minute'
            model_data[:tpm] = quota
          when 'tokens_per_day'
            model_data[:tpd] = quota
          end
        end
        
        # 计算模型整体配额级别（取最低级别）
        model_data[:overall_quota_level] = calculate_model_overall_quota_level(model_data)
        
        result[model_name] = model_data
      end
      
      result
    end

    def calculate_model_overall_quota_level(model_data)
      # 收集所有可用的配额级别
      levels = []
      levels << model_data[:rpm].quota_level if model_data[:rpm]
      levels << model_data[:tpm].quota_level if model_data[:tpm]  
      levels << model_data[:tpd].quota_level if model_data[:tpd]
      
      # 如果没有配额数据，返回未知
      return 'unknown' if levels.empty?
      
      # 过滤掉unknown级别
      valid_levels = levels.reject { |level| level == 'unknown' }
      return 'unknown' if valid_levels.empty?
      
      # 优先级：low > medium > high（取最严格的限制）
      return 'low' if valid_levels.include?('low')
      return 'medium' if valid_levels.include?('medium')
      'high'
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