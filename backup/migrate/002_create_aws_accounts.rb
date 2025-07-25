class CreateAwsAccounts < ActiveRecord::Migration[5.2]
  def change
    create_table :aws_accounts do |t|
      t.string :account_id, null: false, limit: 20
      t.string :access_key, null: false, limit: 100
      t.text :secret_key_encrypted, null: false  # 加密存储
      t.string :secret_key_encrypted_iv, null: false
      t.string :name, null: false, limit: 100
      t.text :description
      t.integer :status, default: 0, null: false  # 0: available, 1: sold_out, 2: maintenance, 3: offline
      t.integer :connection_status, default: 2, null: false  # 0: connected, 1: error, 2: unknown
      t.text :connection_error_message
      t.datetime :last_connection_test_at
      t.datetime :last_quota_update_at
      t.datetime :deleted_at  # 软删除
      
      t.timestamps
    end
    
    add_index :aws_accounts, :account_id, unique: true
    add_index :aws_accounts, :status
    add_index :aws_accounts, :connection_status
    add_index :aws_accounts, :deleted_at
  end
end