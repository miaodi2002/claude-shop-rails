class AddFieldsToAdmins < ActiveRecord::Migration[5.2]
  def change
    add_column :admins, :full_name, :string, limit: 100
    add_column :admins, :role, :integer, default: 0, null: false # 0: admin, 1: super_admin
    add_column :admins, :status, :integer, default: 0, null: false # 0: active, 1: inactive, 2: locked, 3: suspended
    add_column :admins, :password_changed_at, :datetime
    
    # 移除旧的active字段，用新的status字段替代
    remove_column :admins, :active, :boolean
    
    # 添加索引
    add_index :admins, :role
    add_index :admins, :status
  end
end
