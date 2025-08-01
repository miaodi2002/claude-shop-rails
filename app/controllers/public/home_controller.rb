# frozen_string_literal: true

module Public
  class HomeController < Public::BaseController
    def index
      # 获取活跃的AWS账号
      @accounts = AwsAccount.active
                           .includes(account_quotas: :quota_definition)
                           .order(updated_at: :desc)
      
      # 统计信息
      @stats = {
        total_accounts: AwsAccount.active.count,
        available_accounts: AwsAccount.available.count,
        total_models: QuotaDefinition.count,
        last_update: AccountQuota.maximum(:updated_at)
      }
      
      # 获取所有可用的模型类型（用于筛选）
      @available_models = QuotaDefinition.distinct.pluck(:claude_model_name).sort
    end
  end
end