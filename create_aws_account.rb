begin
  account = AwsAccount.create!(
    name: '测试账号',
    account_id: '123456789012',
    access_key: 'AKIAIOSFODNN7EXAMPLE',
    secret_key: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
    region: 'us-east-1',
    status: 'active',
    description: '这是一个测试账号'
  )
  
  puts 'AWS账号创建成功！'
  puts "账号名称: #{account.name}"
  puts "总账号数: #{AwsAccount.count}"
rescue => e
  puts "创建失败: #{e.message}"
  puts "错误详情: #{e.backtrace.first(3).join('\n')}"
end