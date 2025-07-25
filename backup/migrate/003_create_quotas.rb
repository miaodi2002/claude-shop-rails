class CreateQuotas < ActiveRecord::Migration[5.2]
  def change
    create_table :quotas do |t|
      t.references :aws_account, null: false, foreign_key: true
      t.string :model_name, null: false, limit: 100  # Claude模型名称
      t.bigint :quota_limit, default: 0, null: false
      t.bigint :quota_used, default: 0, null: false
      t.bigint :quota_remaining, default: 0, null: false
      t.datetime :last_updated_at
      t.integer :update_status, default: 2, null: false  # 0: success, 1: failed, 2: pending
      t.text :update_error_message
      t.json :raw_data  # 存储AWS返回的原始数据
      
      t.timestamps
    end
    
    add_index :quotas, [:aws_account_id, :model_name], unique: true
    add_index :quotas, :model_name
    add_index :quotas, :update_status
    add_index :quotas, :last_updated_at
  end
end