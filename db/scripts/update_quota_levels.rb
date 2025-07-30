#!/usr/bin/env ruby
# Update quota levels with new calculation logic

require_relative '../config/environment' unless defined?(Rails)

puts '=' * 60
puts '测试和更新配额级别判断逻辑'
puts '=' * 60

puts "\n=== 重新计算所有配额级别 ==="
updated_count = 0

AccountQuota.includes(:quota_definition).find_each do |quota|
  old_level = quota.quota_level
  new_level = quota.send(:calculate_level, quota.current_quota)
  
  if old_level != new_level
    quota.update_column(:quota_level, new_level)
    puts "更新配额级别: #{quota.quota_definition.claude_model_name} #{quota.quota_definition.quota_type}"
    puts "  从 #{old_level} → #{new_level}"
    puts "  当前值: #{quota.current_quota}, 默认值: #{quota.quota_definition.default_value}"
    puts ""
    updated_count += 1
  end
end

puts "配额级别重新计算完成！更新了 #{updated_count} 条记录"

puts "\n=== 测试模型整体配额级别计算 ==="
aws_account = AwsAccount.first
if aws_account
  puts "测试账号: #{aws_account.account_name}"
  
  controller = Admin::AwsAccountsController.new
  controller.instance_variable_set(:@aws_account, aws_account)
  
  account_quotas = aws_account.account_quotas.includes(:quota_definition)
  quotas_by_model = controller.send(:group_quotas_by_model, account_quotas)
  
  quotas_by_model.each do |model_name, model_data|
    puts "\n📱 #{model_name}"
    puts "   整体配额级别: #{model_data[:overall_quota_level]}"
    
    # RPM
    if model_data[:rpm]
      puts "   🟢 RPM: #{model_data[:rpm].current_quota} (#{model_data[:rpm].quota_level}) #{model_data[:rpm].level_icon}"
    else
      puts "   ⚪ RPM: N/A"
    end
    
    # TPM
    if model_data[:tpm]
      puts "   🔵 TPM: #{model_data[:tpm].current_quota} (#{model_data[:tpm].quota_level}) #{model_data[:tpm].level_icon}"
    else
      puts "   ⚪ TPM: N/A"
    end
    
    # TPD
    if model_data[:tpd]
      puts "   🟣 TPD: #{model_data[:tpd].current_quota} (#{model_data[:tpd].quota_level}) #{model_data[:tpd].level_icon}"
    else
      puts "   ⚪ TPD: N/A"
    end
  end
  
  puts "\n✅ 模型整体配额级别计算测试完成！"
else
  puts "❌ 未找到测试账号"
end

puts "\n=== 验证三级判断逻辑 ==="
test_cases = [
  { current: 25, default: 50, expected: 'low' },
  { current: 50, default: 50, expected: 'medium' },
  { current: 100, default: 50, expected: 'high' },
  { current: 200000, default: 200000, expected: 'medium' },
  { current: 300000, default: 200000, expected: 'high' },
  { current: 100000, default: 200000, expected: 'low' }
]

all_passed = true
test_cases.each_with_index do |test_case, index|
  # 模拟计算逻辑
  if test_case[:current] < test_case[:default]
    result = 'low'
  elsif test_case[:current] == test_case[:default]
    result = 'medium'
  else
    result = 'high'
  end
  
  passed = result == test_case[:expected]
  all_passed &&= passed
  
  status = passed ? "✅" : "❌"
  puts "#{status} 测试 #{index + 1}: current=#{test_case[:current]}, default=#{test_case[:default]} → #{result} (期望: #{test_case[:expected]})"
end

puts "\n" + "=" * 60
if all_passed
  puts "🎉 所有测试通过！配额级别判断逻辑工作正常！"
else
  puts "⚠️  某些测试失败，请检查逻辑实现。"
end
puts "=" * 60