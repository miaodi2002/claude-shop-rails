# frozen_string_literal: true

module Public
  class AccountsController < Public::BaseController
    before_action :set_account, only: [:show]
    
    def index
      @accounts = filter_accounts
      @accounts = @accounts.page(params[:page]).per(12) # 每页12个账号
      
      # 筛选选项
      @regions = AwsAccount.public_visible.distinct.pluck(:region).sort
      @models = QuotaDefinition.distinct.pluck(:claude_model_name).sort
      @statuses = [
        ['待售', 'for_sale'],
        ['活跃', 'active'],
        ['已售出', 'sold_out'],
        ['维护中', 'maintenance']
      ]
      
      respond_to do |format|
        format.html
        format.json { render json: @accounts }
      end
    end
    
    def show
      @quotas = @account.account_quotas.includes(:quota_definition)
      
      # 设置页面SEO
      @meta_title = "AWS账号 #{@account.name} - #{@account.region} | Claude Shop"
      @meta_description = "查看AWS账号的Claude模型配额详情，包括#{@quotas.map { |q| q.quota_definition.claude_model_name }.join('、')}"
    end
    
    private
    
    def set_account
      @account = AwsAccount.public_visible.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to public_accounts_path, alert: '账号不存在或已下架'
    end
    
    def filter_accounts
      accounts = AwsAccount.public_visible.includes(account_quotas: :quota_definition)
      
      # 默认筛选为待售状态，如果没有指定状态参数
      status_param = params[:status].present? ? params[:status] : 'for_sale'
      accounts = accounts.where(status: status_param)
      
      # 按区域筛选
      accounts = accounts.where(region: params[:region]) if params[:region].present?
      
      # 按模型筛选
      if params[:model].present?
        accounts = accounts.joins(account_quotas: :quota_definition)
                          .where(quota_definitions: { claude_model_name: params[:model] })
                          .distinct
      end
      
      # 按配额等级筛选
      if params[:quota_level].present?
        accounts = accounts.joins(:account_quotas)
                          .where(account_quotas: { quota_level: params[:quota_level] })
                          .distinct
      end
      
      # 搜索功能
      if params[:q].present?
        accounts = accounts.where('name LIKE ? OR description LIKE ?', 
                                "%#{params[:q]}%", "%#{params[:q]}%")
      end
      
      # 排序
      case params[:sort]
      when 'newest'
        accounts.order(created_at: :desc)
      when 'updated'
        accounts.order(updated_at: :desc)
      when 'name'
        accounts.order(:name)
      else
        accounts.order(updated_at: :desc)
      end
    end
  end
end