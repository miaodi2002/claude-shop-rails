# frozen_string_literal: true

class Admin::CostsController < Admin::BaseController
  before_action :set_aws_account, only: [:show, :sync_account, :chart_data]
  before_action :set_date_range, only: [:index, :show, :chart_data]
  
  # GET /admin/costs
  def index
    @aws_accounts = AwsAccount.active.includes(:daily_costs, :cost_sync_logs)
    
    # Get recent sync logs for status display
    @recent_sync_logs = CostSyncLog.recent.limit(10).includes(:aws_account)
    
    # Calculate summary statistics
    @total_accounts = @aws_accounts.count
    @accounts_with_costs = @aws_accounts.joins(:daily_costs).distinct.count
    @total_cost_last_2_weeks = DailyCost.joins(:aws_account)
                                       .where(aws_accounts: { status: :active })
                                       .by_date_range(@start_date, @end_date)
                                       .sum(:cost_amount)
    
    # Get sync status summary
    @sync_success_rate = CostSyncLog.success_rate
    @last_batch_sync = CostSyncLog.where(sync_type: :batch_sync).recent.first
    
    respond_to do |format|
      format.html
      format.json do
        render json: {
          accounts: @aws_accounts.map { |account| account_summary(account) },
          summary: {
            total_accounts: @total_accounts,
            accounts_with_costs: @accounts_with_costs,
            total_cost_last_2_weeks: @total_cost_last_2_weeks,
            sync_success_rate: @sync_success_rate
          }
        }
      end
    end
  end
  
  # GET /admin/costs/:id
  def show
    @daily_costs = @aws_account.daily_costs
                              .by_date_range(@start_date, @end_date)
                              .ordered_by_date
    
    @cost_sync_logs = @aws_account.cost_sync_logs.recent.limit(20)
    
    # Calculate statistics
    @total_cost = @daily_costs.sum(:cost_amount)
    @average_daily_cost = @daily_costs.average(:cost_amount)&.round(2) || 0
    @highest_daily_cost = @daily_costs.maximum(:cost_amount) || 0
    @days_with_costs = @daily_costs.count
    
    respond_to do |format|
      format.html
      format.json do
        render json: {
          account: account_detail(@aws_account),
          daily_costs: @daily_costs.map { |cost| cost_data(cost) },
          statistics: {
            total_cost: @total_cost,
            average_daily_cost: @average_daily_cost,
            highest_daily_cost: @highest_daily_cost,
            days_with_costs: @days_with_costs
          },
          sync_logs: @cost_sync_logs.map { |log| sync_log_data(log) }
        }
      end
    end
  end
  
  # POST /admin/costs/:id/sync
  def sync_account
    if @aws_account.access_key.blank? || @aws_account.secret_key.blank?
      flash[:error] = "账号 #{@aws_account.name} 缺少AWS凭证，无法同步"
      redirect_to admin_cost_path(@aws_account) and return
    end
    
    # Enqueue sync job
    job_id = CostSyncJob.sync_account(@aws_account.id, @start_date, @end_date)
    
    respond_to do |format|
      format.html do
        flash[:info] = "已启动账号 #{@aws_account.name} 的费用同步任务"
        redirect_to admin_cost_path(@aws_account)
      end
      format.json do
        render json: {
          success: true,
          message: "同步任务已启动",
          job_id: job_id,
          account_id: @aws_account.id
        }
      end
    end
  end
  
  # POST /admin/costs/batch_sync
  def batch_sync
    account_ids = params[:account_ids] || AwsAccount.active.pluck(:id)
    max_concurrency = params[:max_concurrency] || 3
    
    # Validate accounts have credentials
    accounts_without_credentials = AwsAccount.where(id: account_ids)
                                           .where("access_key IS NULL OR access_key = '' OR secret_key_encrypted IS NULL")
                                           .pluck(:name)
    
    if accounts_without_credentials.any?
      error_msg = "以下账号缺少AWS凭证: #{accounts_without_credentials.join(', ')}"
      
      respond_to do |format|
        format.html do
          flash[:error] = error_msg
          redirect_to admin_costs_path
        end
        format.json do
          render json: { success: false, error: error_msg }, status: :unprocessable_entity
        end
      end
      return
    end
    
    # Enqueue batch sync job
    job_id = BatchCostSyncJob.sync_accounts(account_ids, @start_date, @end_date, max_concurrency)
    
    respond_to do |format|
      format.html do
        flash[:info] = "已启动 #{account_ids.count} 个账号的批量同步任务"
        redirect_to admin_costs_path
      end
      format.json do
        render json: {
          success: true,
          message: "批量同步任务已启动",
          job_id: job_id,
          account_count: account_ids.count
        }
      end
    end
  end
  
  # GET /admin/costs/:id/chart_data
  def chart_data
    daily_costs = @aws_account.daily_costs
                             .by_date_range(@start_date, @end_date)
                             .ordered_by_date
    
    chart_data = {
      labels: (@start_date..@end_date).map { |date| date.strftime('%m-%d') },
      datasets: [{
        label: '每日费用 (USD)',
        data: [],
        backgroundColor: 'rgba(59, 130, 246, 0.5)',
        borderColor: 'rgba(59, 130, 246, 1)',
        borderWidth: 1
      }]
    }
    
    # Fill data with actual costs or 0 for missing days
    (@start_date..@end_date).each do |date|
      cost = daily_costs.find { |c| c.date == date }
      chart_data[:datasets][0][:data] << (cost&.cost_amount&.to_f || 0)
    end
    
    render json: chart_data
  end
  
  # GET /admin/costs/sync_status
  def sync_status
    running_logs = CostSyncLog.where(status: :running).includes(:aws_account)
    recent_logs = CostSyncLog.recent.limit(10).includes(:aws_account)
    
    render json: {
      running_syncs: running_logs.map { |log| sync_log_data(log) },
      recent_syncs: recent_logs.map { |log| sync_log_data(log) },
      overall_success_rate: CostSyncLog.success_rate
    }
  end
  
  private
  
  def set_aws_account
    @aws_account = AwsAccount.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html do
        flash[:error] = "未找到指定的AWS账号"
        redirect_to admin_costs_path
      end
      format.json do
        render json: { error: "Account not found" }, status: :not_found
      end
    end
  end
  
  def set_date_range
    @start_date = params[:start_date] ? Date.parse(params[:start_date]) : 2.weeks.ago.to_date
    @end_date = params[:end_date] ? Date.parse(params[:end_date]) : Date.current
    
    # Validate date range
    if @start_date > @end_date
      @start_date, @end_date = @end_date, @start_date
    end
    
    # Limit to reasonable range
    if (@end_date - @start_date).to_i > 90
      @start_date = @end_date - 90.days
    end
  rescue Date::Error
    @start_date = 2.weeks.ago.to_date
    @end_date = Date.current
  end
  
  def account_summary(account)
    {
      id: account.id,
      name: account.name,
      account_id: account.masked_account_id,
      has_cost_data: account.has_cost_data?,
      total_cost_period: account.total_cost_for_period(@start_date, @end_date),
      last_sync: account.latest_cost_sync_log&.created_at,
      sync_status: account.latest_cost_sync_log&.status,
      sync_success_rate: account.cost_sync_success_rate
    }
  end
  
  def account_detail(account)
    {
      id: account.id,
      name: account.name,
      account_id: account.account_id,
      region: account.region,
      status: account.status,
      has_credentials: account.access_key.present? && account.secret_key.present?
    }
  end
  
  def cost_data(daily_cost)
    {
      date: daily_cost.date,
      amount: daily_cost.cost_amount,
      formatted_amount: daily_cost.formatted_cost,
      currency: daily_cost.currency
    }
  end
  
  def sync_log_data(sync_log)
    {
      id: sync_log.id,
      account_name: sync_log.aws_account&.name || 'Batch Sync',
      sync_type: sync_log.sync_type,
      status: sync_log.status,
      synced_dates_count: sync_log.synced_dates_count,
      duration: sync_log.formatted_duration,
      error_message: sync_log.short_error,
      created_at: sync_log.created_at,
      started_at: sync_log.started_at,
      completed_at: sync_log.completed_at
    }
  end
end