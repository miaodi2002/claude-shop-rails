# 公开账号展示控制器
class AccountsController < ApplicationController
  before_action :set_account, only: [:show, :quota_details]
  before_action :set_filter_options, only: [:index, :search, :filter]
  
  # 缓存策略
  caches_action :index, expires_in: 5.minutes, cache_path: proc { |c| 
    c.params.slice(:page, :model, :status, :sort).merge(timestamp: Time.current.to_i / 300)
  }
  
  def index
    @accounts = filtered_accounts
    @stats = account_statistics
    
    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end
  
  def show
    @quotas = @account.quotas.includes(:quota_histories)
    @quota_chart_data = prepare_quota_chart_data
    
    respond_to do |format|
      format.html
      format.json { render json: account_json(@account) }
    end
  end
  
  def search
    @accounts = search_accounts(params[:q])
    
    respond_to do |format|
      format.turbo_stream { render :index }
      format.json { render json: @accounts.map { |account| account_json(account) } }
    end
  end
  
  def filter
    @accounts = filtered_accounts
    
    respond_to do |format|
      format.turbo_stream { render :index }
      format.json { render json: @accounts.map { |account| account_json(account) } }
    end
  end
  
  def quota_details
    @quota = @account.quotas.find_by(model_name: params[:model])
    
    respond_to do |format|
      format.turbo_stream
      format.json { render json: quota_json(@quota) }
    end
  end
  
  private
  
  def set_account
    @account = AwsAccount.public_visible.find(params[:id])
  end
  
  def set_filter_options
    @available_models = Quota.available_models
    @available_statuses = AwsAccount.statuses.keys.select { |s| s.in?(['available', 'sold_out']) }
  end
  
  def filtered_accounts
    scope = AwsAccount.public_visible.includes(:quotas)
    
    # 模型筛选
    if params[:model].present?
      scope = scope.by_model(params[:model])
    end
    
    # 状态筛选
    if params[:status].present? && params[:status].in?(@available_statuses)
      scope = scope.where(status: params[:status])
    end
    
    # 配额筛选
    if params[:has_quota] == 'true'
      scope = scope.with_available_quota
    end
    
    # 排序
    scope = sort_accounts(scope)
    
    # 分页
    scope.page(pagination_params[:page]).per(pagination_params[:per_page])
  end
  
  def search_accounts(query)
    return AwsAccount.none if query.blank?
    
    AwsAccount.public_visible
              .includes(:quotas)
              .where("name ILIKE ? OR account_id ILIKE ? OR description ILIKE ?", 
                     "%#{query}%", "%#{query}%", "%#{query}%")
              .page(pagination_params[:page])
              .per(pagination_params[:per_page])
  end
  
  def sort_accounts(scope)
    case params[:sort]
    when 'name'
      scope.order(name: sort_direction)
    when 'quota'
      scope.joins(:quotas)
           .group('aws_accounts.id')
           .order("SUM(quotas.quota_remaining) #{sort_direction}")
    when 'updated'
      scope.order(last_quota_update_at: sort_direction)
    else
      # 默认排序：可用配额多的在前
      scope.joins(:quotas)
           .group('aws_accounts.id')
           .order('SUM(quotas.quota_remaining) DESC, aws_accounts.created_at DESC')
    end
  end
  
  def sort_direction
    params[:order] == 'asc' ? 'asc' : 'desc'
  end
  
  def account_statistics
    Rails.cache.fetch(cache_key_for('account_stats'), expires_in: 10.minutes) do
      {
        total_accounts: AwsAccount.public_visible.count,
        available_accounts: AwsAccount.available.count,
        total_models: Quota.available_models.count,
        accounts_with_quota: AwsAccount.with_available_quota.count
      }
    end
  end
  
  def prepare_quota_chart_data
    @account.quota_histories
            .where('recorded_at > ?', 7.days.ago)
            .group(:model_name)
            .group_by_day(:recorded_at)
            .sum(:quota_remaining)
  end
  
  def account_json(account)
    {
      id: account.id,
      account_id: account.account_id,
      name: account.name,
      description: account.description,
      status: account.status,
      status_color: account.quota_status_color,
      quotas: account.quotas.map { |quota| quota_json(quota) },
      total_quota_remaining: account.total_quota_remaining,
      models_with_quota: account.models_with_quota,
      telegram_message: telegram_message_for(account),
      last_updated: account.last_quota_update_at&.iso8601
    }
  end
  
  def quota_json(quota)
    return nil unless quota
    
    {
      model_name: quota.model_name,
      quota_limit: quota.quota_limit,
      quota_used: quota.quota_used,
      quota_remaining: quota.quota_remaining,
      usage_percentage: quota.usage_percentage,
      availability_status: quota.availability_status,
      status_color: quota.status_color,
      formatted_limit: quota.formatted_quota_limit,
      formatted_used: quota.formatted_quota_used,
      formatted_remaining: quota.formatted_quota_remaining,
      last_updated: quota.last_updated_at&.iso8601
    }
  end
  
  def telegram_message_for(account)
    quotas_info = account.quotas.with_remaining.map do |quota|
      "#{quota.model_name}: #{quota.formatted_quota_remaining}"
    end.join("\n")
    
    "Hi! 我对以下AWS账号感兴趣：\n\n" \
    "账号ID: #{account.account_id}\n" \
    "账号名称: #{account.name}\n" \
    "可用配额：\n#{quotas_info}\n\n" \
    "请问价格如何？"
  end
end