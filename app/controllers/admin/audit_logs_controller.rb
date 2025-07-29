# frozen_string_literal: true

module Admin
  class AuditLogsController < BaseController
    before_action :set_audit_log, only: [:show]

    def index
      @audit_logs = filtered_logs.includes(:admin, :target)
                                 .recent
                                 .page(params[:page]).per(20)
      
      @log_stats = build_log_stats
      @action_filter_options = build_action_filter_options
      @admin_filter_options = build_admin_filter_options
      @target_type_options = build_target_type_options

      respond_to do |format|
        format.html
        format.json { render json: logs_json }
      end
    end

    def show
      @related_logs = AuditLog.where(target: @audit_log.target)
                              .where.not(id: @audit_log.id)
                              .recent
                              .limit(10)
                              .includes(:admin)
    end

    def export
      logs = filtered_logs.includes(:admin, :target)

      respond_to do |format|
        format.csv do
          csv_data = generate_logs_csv(logs)
          send_data csv_data,
                    filename: "audit_logs_#{Date.current.strftime('%Y%m%d')}.csv",
                    type: 'text/csv'
        end
        format.json do
          render json: {
            logs: logs.limit(1000).as_json(include: [:admin, :target]),
            exported_at: Time.current,
            total_count: logs.count
          }
        end
      end
    end

    private

    def set_audit_log
      @audit_log = AuditLog.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_audit_logs_path, alert: '审计日志不存在'
    end

    def filtered_logs
      scope = AuditLog.all

      # 搜索过滤
      if params[:search].present?
        scope = scope.search(params[:search])
      end

      # 操作类型过滤
      if params[:action_filter].present? && params[:action_filter] != 'all'
        scope = scope.by_action(params[:action_filter])
      end

      # 管理员过滤
      if params[:admin_filter].present? && params[:admin_filter] != 'all'
        scope = scope.by_admin(params[:admin_filter])
      end

      # 目标类型过滤
      if params[:target_type_filter].present? && params[:target_type_filter] != 'all'
        scope = scope.by_target_type(params[:target_type_filter])
      end

      # 成功状态过滤
      case params[:status_filter]
      when 'successful'
        scope = scope.successful
      when 'failed'
        scope = scope.failed
      end

      # 时间范围过滤
      case params[:time_range]
      when 'today'
        scope = scope.today
      when 'week'
        scope = scope.this_week
      when 'month'
        scope = scope.this_month
      when 'custom'
        if params[:start_date].present? && params[:end_date].present?
          start_date = Date.parse(params[:start_date])
          end_date = Date.parse(params[:end_date]).end_of_day
          scope = scope.where(created_at: start_date..end_date)
        end
      end

      scope
    end

    def build_log_stats
      base_scope = AuditLog.all
      base_scope = base_scope.where(created_at: 24.hours.ago..Time.current) if params[:stats_period] == 'today'
      
      {
        total_logs: base_scope.count,
        successful_logs: base_scope.successful.count,
        failed_logs: base_scope.failed.count,
        unique_admins: base_scope.joins(:admin).distinct.count('admins.id'),
        login_attempts: base_scope.where(action: ['login', 'login_failed']).count,
        failed_logins: base_scope.where(action: 'login_failed').count,
        recent_activity: base_scope.where(created_at: 1.hour.ago..Time.current).count
      }
    end

    def build_action_filter_options
      AuditLog.distinct.pluck(:action).compact.sort.map do |action|
        [I18n.t("audit_log.actions.#{action}", default: action.humanize), action]
      end
    end

    def build_admin_filter_options
      AdminUser.joins("INNER JOIN audit_logs ON audit_logs.admin_id = admins.id")
               .distinct
               .pluck(:id, :username)
               .map { |id, username| [username, id] }
               .sort_by(&:first)
    end

    def build_target_type_options
      AuditLog.distinct.pluck(:target_type).compact.sort.map do |type|
        [I18n.t("models.#{type.underscore}", default: type), type]
      end
    end

    def logs_json
      {
        logs: @audit_logs.map do |log|
          log.as_json(
            include: {
              admin: { only: [:id, :username, :email] },
              target: { only: [:id] }
            },
            methods: [:display_action, :target_display_name, :changes_summary]
          )
        end,
        pagination: {
          page: @audit_logs.current_page,
          pages: @audit_logs.total_pages,
          count: @audit_logs.total_count,
          per_page: @audit_logs.limit_value
        },
        stats: @log_stats
      }
    end

    def generate_logs_csv(logs)
      require 'csv'

      CSV.generate(headers: true) do |csv|
        csv << [
          'ID', '时间', '管理员', '操作', '目标类型', '目标名称', 
          'IP地址', '用户代理', '是否成功', '错误信息', '变更详情'
        ]

        logs.find_each do |log|
          csv << [
            log.id,
            log.created_at.strftime('%Y-%m-%d %H:%M:%S'),
            log.admin&.username || '系统',
            log.display_action,
            log.target_type,
            log.target_display_name,
            log.ip_address,
            log.user_agent&.truncate(50),
            log.successful? ? '成功' : '失败',
            log.error_message,
            log.changes_summary
          ]
        end
      end
    end
  end
end