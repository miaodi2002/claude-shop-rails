# frozen_string_literal: true

module Admin
  class QuotasController < BaseController
    before_action :set_aws_account, only: [:account_quotas, :refresh_account_quotas]
    before_action :set_quota, only: [:show, :update, :refresh]

    def index
      @quotas = filtered_quotas.includes(:aws_account)
                               .order(:service_name, :aws_account_id)
                               .page(params[:page]).per(20)
      
      @quota_summary = build_quota_summary
      @model_stats = build_model_stats
      
      respond_to do |format|
        format.html
        format.json { render json: quotas_json }
      end
    end

    def show
      @quota_histories = @quota.quota_histories
                               .recent
                               .limit(50)
      @usage_trend = build_usage_trend(@quota)
    end

    # 按账号查看配额
    def account_quotas
      @quotas = @aws_account.quotas.includes(:quota_histories)
      @total_quota_remaining = @quotas.sum(:quota_remaining)
      @total_quota_used = @quotas.sum(:quota_used)
      @last_refresh = @quotas.maximum(:last_updated_at)
    end

    # 更新单个配额
    def update
      old_values = {
        quota_limit: @quota.quota_limit,
        quota_used: @quota.quota_used,
        quota_remaining: @quota.quota_remaining
      }

      if @quota.update(quota_params)
        audit_log('update_quota', "手动更新配额: #{@quota.service_name}", {
          old_values: old_values,
          new_values: quota_params
        })
        
        redirect_to admin_quota_path(@quota), notice: '配额更新成功'
      else
        render :show, status: :unprocessable_entity
      end
    end

    # 刷新单个配额
    def refresh
      @quota.refresh!
      audit_log('refresh_quota', "刷新配额: #{@quota.service_name}")
      redirect_to admin_quota_path(@quota), notice: '配额刷新成功'
    rescue => e
      redirect_to admin_quota_path(@quota), alert: "刷新失败: #{e.message}"
    end

    # 刷新账号所有配额
    def refresh_account_quotas
      @aws_account.refresh_quotas!
      audit_log('refresh_account_quotas', "刷新账号配额: #{@aws_account.name}")
      redirect_to admin_account_quotas_path(@aws_account), notice: '账号配额刷新成功'
    rescue => e
      redirect_to admin_account_quotas_path(@aws_account), alert: "刷新失败: #{e.message}"
    end

    # 批量刷新
    def bulk_refresh
      service_names = params[:service_names]&.reject(&:blank?)
      account_ids = params[:account_ids]&.reject(&:blank?)

      if service_names.blank? && account_ids.blank?
        redirect_to admin_quotas_path, alert: '请选择要刷新的配额或账号'
        return
      end

      scope = Quota.all
      scope = scope.where(service_name: service_names) if service_names.present?
      scope = scope.where(aws_account_id: account_ids) if account_ids.present?

      quotas = scope.includes(:aws_account)
      
      if quotas.any?
        BulkQuotaRefreshJob.perform_later(quotas.pluck(:id))
        audit_log('bulk_refresh_quotas', "批量刷新 #{quotas.count} 个配额")
        redirect_to admin_quotas_path, notice: "已启动 #{quotas.count} 个配额的批量刷新"
      else
        redirect_to admin_quotas_path, alert: '没有找到符合条件的配额'
      end
    end

    # 配额使用统计
    def statistics
      @date_range = params[:date_range] || '7_days'
      @service_filter = params[:service_filter]
      @account_filter = params[:account_filter]

      @usage_trends = build_usage_trends
      @model_comparison = build_model_comparison
      @account_usage = build_account_usage
      @quota_alerts = build_quota_alerts

      respond_to do |format|
        format.html
        format.json { render json: statistics_json }
      end
    end

    # 导出配额数据
    def export
      quotas = filtered_quotas.includes(:aws_account, :quota_histories)

      respond_to do |format|
        format.csv do
          csv_data = generate_quotas_csv(quotas)
          send_data csv_data,
                    filename: "quotas_#{Date.current.strftime('%Y%m%d')}.csv",
                    type: 'text/csv'
        end
        format.json do
          render json: {
            quotas: quotas.as_json(include: [:aws_account, :quota_histories]),
            exported_at: Time.current,
            total_count: quotas.count
          }
        end
      end
    end

    private

    def set_aws_account
      @aws_account = AwsAccount.find(params[:aws_account_id] || params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_quotas_path, alert: 'AWS账号不存在'
    end

    def set_quota
      @quota = Quota.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_quotas_path, alert: '配额记录不存在'
    end

    def quota_params
      params.require(:quota).permit(:quota_limit, :quota_used)
    end

    def filtered_quotas
      scope = Quota.all

      # 搜索过滤
      if params[:search].present?
        search_term = "%#{params[:search]}%"
        scope = scope.joins(:aws_account).where(
          "quotas.service_name LIKE ? OR aws_accounts.name LIKE ? OR aws_accounts.account_id LIKE ?",
          search_term, search_term, search_term
        )
      end

      # 服务过滤
      if params[:service_name].present? && params[:service_name] != 'all'
        scope = scope.where(service_name: params[:service_name])
      end

      # 账号过滤
      if params[:aws_account_id].present? && params[:aws_account_id] != 'all'
        scope = scope.where(aws_account_id: params[:aws_account_id])
      end

      # 状态过滤
      case params[:status_filter]
      when 'healthy'
        scope = scope.where('quota_remaining > quota_limit * 0.5')
      when 'warning'
        scope = scope.where('quota_remaining BETWEEN quota_limit * 0.1 AND quota_limit * 0.5')
      when 'critical'
        scope = scope.where('quota_remaining <= quota_limit * 0.1 AND quota_remaining > 0')
      when 'exhausted'
        scope = scope.where(quota_remaining: 0)
      end

      # 更新状态过滤
      if params[:update_status].present? && params[:update_status] != 'all'
        scope = scope.where(update_status: params[:update_status])
      end

      scope
    end

    def build_quota_summary
      {
        total_quotas: Quota.count,
        total_limit: Quota.sum(:quota_limit),
        total_used: Quota.sum(:quota_used),
        total_remaining: Quota.sum(:quota_remaining),
        healthy_count: Quota.where('quota_remaining > quota_limit * 0.5').count,
        warning_count: Quota.where('quota_remaining BETWEEN quota_limit * 0.1 AND quota_limit * 0.5').count,
        critical_count: Quota.where('quota_remaining <= quota_limit * 0.1 AND quota_remaining > 0').count,
        exhausted_count: Quota.where(quota_remaining: 0).count
      }
    end

    def build_model_stats
      Quota.group(:service_name).group(:update_status).count
    end

    def build_usage_trend(quota)
      quota.quota_histories
           .for_period(7.days.ago, Time.current)
           .group("DATE(recorded_at)")
           .average(:quota_used)
    end

    def build_usage_trends
      days = case @date_range
             when '24_hours' then 1.days.ago
             when '7_days' then 7.days.ago
             when '30_days' then 30.days.ago
             else 7.days.ago
             end

      scope = QuotaHistory.for_period(days, Time.current)
      scope = scope.for_service(@service_filter) if @service_filter.present?
      scope = scope.where(aws_account_id: @account_filter) if @account_filter.present?

      scope.group("DATE(recorded_at)")
           .group(:service_name)
           .average(:quota_used)
    end

    def build_model_comparison
      Quota.joins(:aws_account)
           .where(aws_accounts: { status: :active })
           .group(:service_name)
           .group('aws_accounts.name')
           .sum(:quota_remaining)
    end

    def build_account_usage
      AwsAccount.joins(:quotas)
                .where(status: :active)
                .group('aws_accounts.name')
                .sum('quotas.quota_used')
    end

    def build_quota_alerts
      {
        exhausted: Quota.joins(:aws_account)
                       .where(quota_remaining: 0, aws_accounts: { status: :active })
                       .count,
        critical: Quota.joins(:aws_account)
                      .where('quota_remaining <= quota_limit * 0.1 AND quota_remaining > 0')
                      .where(aws_accounts: { status: :active })
                      .count,
        stale: Quota.joins(:aws_account)
                   .where('last_updated_at < ? OR last_updated_at IS NULL', 24.hours.ago)
                   .where(aws_accounts: { status: :active })
                   .count
      }
    end

    def quotas_json
      {
        quotas: @quotas.map do |quota|
          quota.as_json(
            include: {
              aws_account: { only: [:id, :name, :account_id, :status] }
            },
            methods: [:usage_percentage, :remaining_percentage, :status_indicator]
          )
        end,
        pagination: {
          page: @quotas.current_page,
          pages: @quotas.total_pages,
          count: @quotas.total_count,
          per_page: @quotas.limit_value
        },
        summary: @quota_summary,
        model_stats: @model_stats
      }
    end

    def statistics_json
      {
        usage_trends: @usage_trends,
        model_comparison: @model_comparison,
        account_usage: @account_usage,
        quota_alerts: @quota_alerts,
        date_range: @date_range,
        filters: {
          service: @service_filter,
          account: @account_filter
        }
      }
    end

    def generate_quotas_csv(quotas)
      require 'csv'

      CSV.generate(headers: true) do |csv|
        csv << [
          'ID', 'AWS账号', '账号ID', '服务名称', '配额限制', '已使用', '剩余配额',
          '使用率(%)', '更新状态', '最后更新时间', '创建时间'
        ]

        quotas.each do |quota|
          csv << [
            quota.id,
            quota.aws_account.name,
            quota.aws_account.account_id,
            quota.service_name,
            quota.quota_limit,
            quota.quota_used,
            quota.quota_remaining,
            quota.usage_percentage,
            I18n.t("quota.update_status.#{quota.update_status}"),
            quota.last_updated_at&.strftime('%Y-%m-%d %H:%M'),
            quota.created_at.strftime('%Y-%m-%d %H:%M')
          ]
        end
      end
    end

    def audit_log(action, details, metadata = {})
      AuditLog.log_action(action,
        admin: current_admin,
        target: @quota,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        successful: true,
        metadata: { details: details }.merge(metadata)
      )
    end
  end
end