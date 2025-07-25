class AccountCardComponent < ViewComponent::Base
  def initialize(account:, show_details: false, admin_view: false)
    @account = account
    @show_details = show_details
    @admin_view = admin_view
  end
  
  private
  
  attr_reader :account, :show_details, :admin_view
  
  def card_classes
    base_classes = %w[
      bg-white rounded-lg border shadow-sm hover:shadow-md 
      transition-all duration-200 overflow-hidden
    ]
    
    status_classes = case account.status
    when 'available'
      account.has_available_quota? ? %w[border-green-200 hover:border-green-300] : %w[border-yellow-200 hover:border-yellow-300]
    when 'sold_out'
      %w[border-red-200 hover:border-red-300]
    when 'maintenance'
      %w[border-orange-200 hover:border-orange-300]
    else
      %w[border-gray-200 hover:border-gray-300]
    end
    
    (base_classes + status_classes).join(' ')
  end
  
  def status_badge_classes
    base_classes = %w[inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium]
    
    status_classes = case account.status
    when 'available'
      %w[bg-green-100 text-green-800]
    when 'sold_out'
      %w[bg-red-100 text-red-800]
    when 'maintenance'
      %w[bg-orange-100 text-orange-800]
    else
      %w[bg-gray-100 text-gray-800]
    end
    
    (base_classes + status_classes).join(' ')
  end
  
  def status_text
    case account.status
    when 'available'
      account.has_available_quota? ? '可购买' : '配额不足'
    when 'sold_out'
      '已售罄'
    when 'maintenance'
      '维护中'
    when 'offline'
      '已下架'
    else
      '未知状态'
    end
  end
  
  def primary_quotas
    account.quotas.with_remaining.limit(3)
  end
  
  def remaining_quota_count
    account.quotas.with_remaining.count - 3
  end
  
  def telegram_url
    message = telegram_message
    encoded_message = CGI.escape(message)
    
    # 从系统配置获取Telegram联系方式
    telegram_username = SystemConfig.get_value('telegram_username', 'claudeshop')
    
    "https://t.me/#{telegram_username}?text=#{encoded_message}"
  end
  
  def telegram_message
    quotas_info = account.quotas.with_remaining.map do |quota|
      "#{quota.model_name}: #{quota.formatted_quota_remaining}"
    end.join("\n")
    
    "Hi! 我对以下AWS账号感兴趣：\n\n" \
    "账号ID: #{account.account_id}\n" \
    "账号名称: #{account.name}\n" \
    "可用配额：\n#{quotas_info}\n\n" \
    "请问价格如何？"
  end
  
  def last_update_text
    return '未更新' unless account.last_quota_update_at
    
    time_ago = time_ago_in_words(account.last_quota_update_at)
    "#{time_ago}前更新"
  end
  
  def connection_status_icon
    case account.connection_status
    when 'connected'
      content_tag :span, '●', class: 'text-green-500', title: '连接正常'
    when 'error'
      content_tag :span, '●', class: 'text-red-500', title: '连接异常'
    else
      content_tag :span, '●', class: 'text-gray-400', title: '未知状态'
    end
  end
end