# frozen_string_literal: true

module PublicHelper
  # Telegram联系链接
  def telegram_contact_link(account, options = {})
    text = options[:text] || '联系购买'
    css_class = options[:class] || 'bg-blue-500 text-white px-4 py-2 rounded-lg hover:bg-blue-600 transition'
    custom_message = options[:message]
    
    url = TelegramService.contact_link(account, custom_message: custom_message)
    
    link_to url, target: '_blank', class: css_class do
      content = []
      
      if options[:icon] != false
        content << content_tag(:svg, class: 'inline w-5 h-5 mr-2', fill: 'currentColor', viewBox: '0 0 24 24') do
          tag(:path, d: 'M12 0C5.373 0 0 5.373 0 12s5.373 12 12 12 12-5.373 12-12S18.627 0 12 0zm5.894 8.221l-1.97 9.28c-.145.658-.537.818-1.084.508l-3-2.21-1.446 1.394c-.14.18-.357.295-.6.295-.002 0-.003 0-.005 0l.213-3.054 5.56-5.022c.24-.213-.054-.334-.373-.121l-6.869 4.326-2.96-.924c-.64-.203-.657-.64.135-.954l11.566-4.458c.538-.196 1.006.128.832.941z')
        end
      end
      
      content << text
      safe_join(content)
    end
  end
  
  # 批量询价链接
  def telegram_bulk_inquiry_link(accounts, options = {})
    text = options[:text] || '批量询价'
    css_class = options[:class] || 'bg-green-500 text-white px-4 py-2 rounded-lg hover:bg-green-600 transition'
    
    message = TelegramService.generate_bulk_inquiry_message(accounts)
    url = "https://t.me/#{TelegramService::TELEGRAM_USERNAME.gsub('@', '')}?text=#{CGI.escape(message)}"
    
    link_to text, url, target: '_blank', class: css_class
  end
  
  # 通用联系链接
  def telegram_general_contact_link(options = {})
    text = options[:text] || '联系我们'
    css_class = options[:class] || 'text-blue-600 hover:text-blue-700'
    
    message = TelegramService.generate_general_contact_message
    url = "https://t.me/#{TelegramService::TELEGRAM_USERNAME.gsub('@', '')}?text=#{CGI.escape(message)}"
    
    link_to text, url, target: '_blank', class: css_class
  end
  
  # 格式化配额等级
  def quota_level_badge(level)
    case level
    when 'high'
      content_tag(:span, '高配额', class: 'px-2 py-1 text-xs font-medium rounded-full bg-green-100 text-green-800')
    when 'low'
      content_tag(:span, '标准配额', class: 'px-2 py-1 text-xs font-medium rounded-full bg-blue-100 text-blue-800')
    else
      content_tag(:span, '未知', class: 'px-2 py-1 text-xs font-medium rounded-full bg-gray-100 text-gray-800')
    end
  end
  
  # 格式化账号状态
  def account_status_badge(status)
    case status
    when 'active'
      content_tag(:span, '可用', class: 'px-3 py-1 text-sm font-medium rounded-full bg-green-100 text-green-800')
    when 'sold_out'
      content_tag(:span, '已售出', class: 'px-3 py-1 text-sm font-medium rounded-full bg-red-100 text-red-800')
    when 'maintenance'
      content_tag(:span, '维护中', class: 'px-3 py-1 text-sm font-medium rounded-full bg-yellow-100 text-yellow-800')
    else
      content_tag(:span, '不可用', class: 'px-3 py-1 text-sm font-medium rounded-full bg-gray-100 text-gray-800')
    end
  end
  
  # 简化模型名称显示
  def simplified_model_name(full_name)
    # 从 "Claude 3.5 Sonnet - Text" 提取 "Claude 3.5 Sonnet"
    full_name.split(' - ').first
  end
  
  # 检查是否有高配额
  def has_high_quota?(account)
    account.account_quotas.high_level.exists?
  end
  
  # 生成账号摘要信息
  def account_summary(account)
    quotas = account.account_quotas.includes(:quota_definition)
    high_count = quotas.high_level.count
    total_count = quotas.count
    models_count = quotas.map { |q| simplified_model_name(q.quota_definition.claude_model_name) }.uniq.count
    
    summary = []
    summary << "#{total_count}个配额"
    summary << "#{high_count}个高配额" if high_count > 0
    summary << "支持#{models_count}种模型"
    
    summary.join(' • ')
  end
end