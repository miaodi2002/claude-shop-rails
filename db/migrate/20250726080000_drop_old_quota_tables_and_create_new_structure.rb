# frozen_string_literal: true

class DropOldQuotaTablesAndCreateNewStructure < ActiveRecord::Migration[8.0]
  def change
    # 删除旧表和外键约束
    if table_exists?(:quota_histories)
      remove_foreign_key :quota_histories, :quotas if foreign_key_exists?(:quota_histories, :quotas)
      remove_foreign_key :quota_histories, :aws_accounts if foreign_key_exists?(:quota_histories, :aws_accounts)
      drop_table :quota_histories
    end
    
    drop_table :quotas if table_exists?(:quotas)
    
    # 创建配额定义表
    create_table :quota_definitions do |t|
      t.string :quota_code, null: false
      t.string :model_name, null: false
      t.string :model_version
      t.string :quota_type, null: false
      t.text :quota_name, null: false
      t.string :call_type
      t.decimal :default_value, precision: 15, scale: 2
      t.boolean :is_active, default: true
      
      t.timestamps
    end
    
    add_index :quota_definitions, :quota_code, unique: true
    add_index :quota_definitions, [:model_name, :quota_type]
    add_index :quota_definitions, :is_active
    
    # 创建账号配额表
    create_table :account_quotas do |t|
      t.references :aws_account, null: false, foreign_key: true
      t.references :quota_definition, null: false, foreign_key: true
      t.decimal :current_quota, precision: 15, scale: 2, default: 0
      t.string :quota_level, default: 'unknown'
      t.boolean :is_adjustable, default: false
      t.datetime :last_sync_at
      t.string :sync_status, default: 'pending'
      t.text :sync_error
      
      t.timestamps
    end
    
    add_index :account_quotas, [:aws_account_id, :quota_definition_id], unique: true, name: 'idx_account_quota_unique'
    add_index :account_quotas, :sync_status
    add_index :account_quotas, :quota_level
  end
end