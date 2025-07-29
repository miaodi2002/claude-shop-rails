begin
  account = AwsAccount.create!(
    name: '开发环境账号',
    account_id: '987654321098',
    access_key: 'AKIAIOSFODNN7EXAMPLE2',
    secret_key: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY2',
    region: 'us-west-2',
    status: 'active',
    description: '开发和测试使用的AWS账号'
  )
  
  puts "账号创建成功: #{account.name}"
  puts "总账号数: #{AwsAccount.count}"
rescue => e
  puts "创建失败: #{e.message}"
  puts "错误详情: #{e.backtrace.first(3).join('\n')}"
end