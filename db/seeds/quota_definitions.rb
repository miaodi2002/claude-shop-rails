# frozen_string_literal: true

# Seeds for quota definitions
puts "Seeding quota definitions..."

# 使用 AwsQuotaService 的预定义数据
count = AwsQuotaService.sync_quota_definitions!

puts "✅ Successfully seeded #{count} quota definitions"

# 列出所有配额定义
puts "\nCurrent quota definitions: #{QuotaDefinition.count} total"