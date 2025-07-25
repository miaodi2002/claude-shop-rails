class CreateAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :audit_logs do |t|
      t.references :admin, null: true, foreign_key: true  # null for system operations
      t.string :action, null: false, limit: 50  # create, update, delete, login, logout, refresh_quota
      t.string :target_type, limit: 50  # AwsAccount, Admin, Quota
      t.bigint :target_id
      t.json :changes  # 变更内容
      t.json :metadata  # 额外元数据
      t.string :ip_address, limit: 45  # IPv6 compatible
      t.text :user_agent
      t.boolean :successful, default: true, null: false
      t.text :error_message
      
      t.timestamps
    end
    
    add_index :audit_logs, :action
    add_index :audit_logs, [:target_type, :target_id]
    add_index :audit_logs, :created_at
    add_index :audit_logs, :successful
  end
end