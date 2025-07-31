# frozen_string_literal: true

class TelegramService
  TELEGRAM_USERNAME = '@claudeshop'.freeze
  
  class << self
    # 生成联系购买的Telegram深度链接
    def contact_link(account, custom_message: nil)
      message = custom_message || generate_contact_message(account)
      "https://t.me/#{TELEGRAM_USERNAME.gsub('@', '')}?text=#{CGI.escape(message)}"
    end
    
    # 生成账号详情的Telegram消息
    def generate_contact_message(account)
      quotas_summary = generate_quotas_summary(account)
      
      "🤖 Claude Shop - 账号咨询

📋 账号信息:
• 名称: #{account.name}
• ID: #{account.account_id || '未设置'}
• 区域: #{account.region}
• 状态: #{account.display_status}

💰 配额详情:
#{quotas_summary}

📞 我想了解这个账号的详细信息和价格，请联系我！

---
发送时间: #{Time.current.strftime('%Y-%m-%d %H:%M')}"
    end
    
    # 生成询价消息
    def generate_inquiry_message(account, user_contact: nil)
      "💰 Claude Shop - 询价

我对以下账号感兴趣:
• 账号: #{account.name}
• 区域: #{account.region}
• 配额数: #{account.account_quotas.count}个

#{user_contact ? "联系方式: #{user_contact}" : ''}

请告知价格和可用性，谢谢！"
    end
    
    # 生成通用联系消息
    def generate_general_contact_message
      "👋 你好！我想了解AWS Bedrock Claude配额账号的相关信息。

我的需求:
• 使用场景: [请填写]
• 预算范围: [请填写] 
• 配额要求: [请填写]

期待您的回复！"
    end
    
    # 生成批量购买询价
    def generate_bulk_inquiry_message(accounts)
      account_list = accounts.map.with_index(1) do |account, index|
        "#{index}. #{account.name} (#{account.region}) - #{account.account_quotas.count}个配额"
      end.join("\n")
      
      "🛒 Claude Shop - 批量询价

我想批量购买以下账号:
#{account_list}

请提供:
• 批量优惠价格
• 可用性确认
• 交付时间

谢谢！"
    end
    
    private
    
    def generate_quotas_summary(account)
      quotas = account.account_quotas.includes(:quota_definition)
      return "• 暂无配额信息" if quotas.empty?
      
      # 按模型分组
      models = quotas.group_by { |q| q.quota_definition.claude_model_name.split(' - ').last }
      
      summary = models.map do |model, model_quotas|
        high_count = model_quotas.count { |q| q.quota_level == 'high' }
        low_count = model_quotas.count { |q| q.quota_level == 'low' }
        
        level_info = []
        level_info << "#{high_count}个高配额" if high_count > 0
        level_info << "#{low_count}个标准配额" if low_count > 0
        
        "• #{model}: #{level_info.join(', ')}"
      end
      
      summary.join("\n")
    end
  end
end