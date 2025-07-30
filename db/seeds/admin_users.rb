# Create initial admin user
puts "🔧 Creating initial admin user..."

admin_user = AdminUser.find_or_create_by(email: 'admin@example.com') do |admin|
  admin.username = 'admin'
  admin.email = 'admin@example.com'
  admin.password = 'Admin123!@#'
  admin.password_confirmation = 'Admin123!@#'
  admin.full_name = '系统管理员'
  admin.role = 'super_admin'
  admin.status = 'active'
  admin.password_changed_at = Time.current
end

if admin_user.persisted?
  puts "✅ Admin user created successfully:"
  puts "   Email: #{admin_user.email}"
  puts "   Username: #{admin_user.username}"
  puts "   Role: #{admin_user.role}"
  puts "   Password: Admin123!@# (请登录后立即修改)"
else
  puts "❌ Failed to create admin user:"
  admin_user.errors.full_messages.each do |error|
    puts "   - #{error}"
  end
end