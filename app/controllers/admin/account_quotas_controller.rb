# frozen_string_literal: true

module Admin
  class AccountQuotasController < BaseController
    before_action :set_aws_account, only: [:account_quotas, :refresh_account_quotas]
    before_action :set_account_quota, only: [:show, :update, :refresh]

    def index
      @account_quotas = filtered_account_quotas.includes(:aws_account, :quota_definition)
                                              .joins(:quota_definition)
                                              .order('quota_definitions.quota_name', :aws_account_id)
                                              .page(params[:page]).per(20)
      
      @quota_summary = build_quota_summary
      @model_stats = build_model_stats
      
      respond_to do |format|
        format.html
        format.json { render json: account_quotas_json }
      end
    end

    def show
      @related_quotas = AccountQuota.joins(:quota_definition)
                                   .where(quota_definition: { claude_model_name: @account_quota.quota_definition.claude_model_name })
                                   .where.not(id: @account_quota.id)
                                   .includes(:aws_account, :quota_definition)
                                   .limit(10)
    end

    # 按账号查看配额
    def account_quotas
      @account_quotas = @aws_account.account_quotas.includes(:quota_definition)
                                                  .joins(:quota_definition)
                                                  .order('quota_definitions.quota_name')
      @total_current_quota = @account_quotas.sum(:current_quota)
      @active_quotas_count = @account_quotas.where('current_quota > 0').count
      @last_sync = @account_quotas.maximum(:last_sync_at)
    end

    # 更新单个配额
    def update
      old_quota = @account_quota.current_quota

      if @account_quota.update(account_quota_params)
        audit_log('update_quota', "手动更新配额: #{@account_quota.quota_definition.service_name}", {
          aws_account: @account_quota.aws_account.name,
          old_quota: old_quota,
          new_quota: @account_quota.current_quota
        })
        
        redirect_to admin_account_quota_path(@account_quota), 
                    notice: '配额更新成功'
      else
        render :show, status: :unprocessable_entity
      end
    end

    # 刷新单个配额
    def refresh
      RefreshQuotaJob.perform_later(@account_quota.aws_account.id, { 
        quota_definition_id: @account_quota.quota_definition.id,
        job_type: :manual 
      })
      
      audit_log('refresh_quota', "手动刷新配额: #{@account_quota.quota_definition.service_name}", {
        aws_account: @account_quota.aws_account.name
      })
      
      redirect_to admin_account_quota_path(@account_quota), 
                  notice: '配额刷新任务已启动'
    end

    # 刷新账号所有配额
    def refresh_account_quotas
      RefreshQuotaJob.perform_later(@aws_account.id, { job_type: :manual })
      
      audit_log('refresh_account_quotas', "刷新账号所有配额: #{@aws_account.name}")
      
      redirect_to account_quotas_admin_aws_account_path(@aws_account), 
                  notice: '账号配额刷新任务已启动'
    end

    # 批量刷新
    def bulk_refresh
      quota_ids = params[:quota_ids]&.reject(&:blank?)
      
      if quota_ids.blank?
        redirect_to admin_account_quotas_path, alert: '请选择要刷新的配额'
        return
      end
      
      account_quotas = AccountQuota.includes(:aws_account, :quota_definition)
                                  .where(id: quota_ids)
      
      if account_quotas.any?
        # 按账号分组，为每个账号创建刷新任务
        account_quotas.group_by(&:aws_account).each do |aws_account, quotas|
          quota_definition_ids = quotas.map { |q| q.quota_definition.id }
          RefreshQuotaJob.perform_later(aws_account.id, { 
            quota_definition_ids: quota_definition_ids,
            job_type: :bulk_manual 
          })
        end
        
        audit_log('bulk_refresh_quotas', "批量刷新 #{account_quotas.count} 个配额")
        redirect_to admin_account_quotas_path, notice: "已启动 #{account_quotas.count} 个配额的刷新任务"
      else
        redirect_to admin_account_quotas_path, alert: '没有找到有效的配额'
      end
    end

    # 统计信息
    def statistics
      @stats = {
        total_quotas: AccountQuota.count,
        active_quotas: AccountQuota.where('current_quota > 0').count,
        high_level_quotas: AccountQuota.where(quota_level: 'high').count,
        synced_quotas: AccountQuota.where(sync_status: 'completed').count,
        failed_quotas: AccountQuota.where(sync_status: 'failed').count
      }

      @model_distribution = AccountQuota.joins(:quota_definition)
                                       .group('quota_definitions.claude_model_name')
                                       .count

      @quota_level_distribution = AccountQuota.group(:quota_level).count

      respond_to do |format|
        format.html
        format.json { render json: @stats.merge(
          model_distribution: @model_distribution,
          quota_level_distribution: @quota_level_distribution
        )}
      end
    end

    # 导出数据
    def export
      account_quotas = filtered_account_quotas.includes(:aws_account, :quota_definition)
      
      respond_to do |format|
        format.csv do
          csv_data = generate_csv(account_quotas)
          send_data csv_data, 
                    filename: "account_quotas_#{Date.current.strftime('%Y%m%d')}.csv",
                    type: 'text/csv'
        end
        format.json do
          render json: {
            account_quotas: account_quotas.as_json(
              include: [:aws_account, :quota_definition]
            ),
            exported_at: Time.current,
            total_count: account_quotas.count
          }
        end
      end
    end

    private

    def set_aws_account
      @aws_account = AwsAccount.find(params[:id] || params[:aws_account_id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_aws_accounts_path, alert: '账号不存在'
    end

    def set_account_quota
      @account_quota = AccountQuota.includes(:aws_account, :quota_definition)
                                  .find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_account_quotas_path, alert: '配额不存在'
    end

    def account_quota_params
      params.require(:account_quota).permit(:current_quota, :quota_level, :is_adjustable)
    end

    def filtered_account_quotas
      scope = AccountQuota.all

      # 搜索过滤
      if params[:search].present?
        search_term = "%#{params[:search]}%"
        scope = scope.joins(:aws_account, :quota_definition)
                     .where(
                       "aws_accounts.name LIKE ? OR quota_definitions.quota_name LIKE ? OR quota_definitions.claude_model_name LIKE ?",
                       search_term, search_term, search_term
                     )
      end

      # 模型过滤
      if params[:model].present? && params[:model] != 'all'
        scope = scope.joins(:quota_definition)
                     .where(quota_definitions: { claude_model_name: params[:model] })
      end

      # 等级过滤
      if params[:level].present? && params[:level] != 'all'
        scope = scope.where(quota_level: params[:level])
      end

      # 状态过滤
      if params[:status].present? && params[:status] != 'all'
        case params[:status]
        when 'active'
          scope = scope.where('current_quota > 0')
        when 'inactive'
          scope = scope.where(current_quota: 0)
        when 'sync_failed'
          scope = scope.where(sync_status: 'failed')
        end
      end

      scope
    end

    def build_quota_summary
      {
        total: AccountQuota.count,
        active: AccountQuota.where('current_quota > 0').count,
        high_level: AccountQuota.where(quota_level: 'high').count,
        low_level: AccountQuota.where(quota_level: 'low').count,
        sync_failed: AccountQuota.where(sync_status: 'failed').count
      }
    end

    def build_model_stats
      AccountQuota.joins(:quota_definition)
                  .group('quota_definitions.claude_model_name')
                  .group(:quota_level)
                  .count
    end

    def account_quotas_json
      {
        account_quotas: @account_quotas.map do |quota|
          quota.as_json(
            include: {
              aws_account: { only: [:id, :name, :account_id, :status] },
              quota_definition: { only: [:id, :service_name, :claude_model_name, :quota_type] }
            },
            methods: [:display_quota_level, :sync_status_display]
          )
        end,
        pagination: {
          page: @account_quotas.current_page,
          pages: @account_quotas.total_pages,
          count: @account_quotas.total_count,
          per_page: @account_quotas.limit_value
        },
        summary: @quota_summary,
        model_stats: @model_stats
      }
    end

    def generate_csv(account_quotas)
      require 'csv'
      
      CSV.generate(headers: true) do |csv|
        csv << [
          'ID', 'AWS账号', '配额名称', 'Claude模型', '配额类型', 
          '当前配额', '配额等级', '是否可调整', '同步状态', '最后同步时间'
        ]
        
        account_quotas.each do |quota|
          csv << [
            quota.id,
            quota.aws_account.name,
            quota.quota_definition.quota_name,
            quota.quota_definition.claude_model_name,
            quota.quota_definition.quota_type,
            quota.current_quota,
            quota.quota_level,
            quota.is_adjustable? ? '是' : '否',
            quota.sync_status,
            quota.last_sync_at&.strftime('%Y-%m-%d %H:%M')
          ]
        end
      end
    end

    def audit_log(action, details, metadata = {})
      AuditLog.log_action(action,
        admin: current_admin,
        target: @account_quota || @aws_account,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        successful: true,
        metadata: { details: details }.merge(metadata)
      )
    end
  end
end