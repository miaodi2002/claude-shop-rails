class CreateQuotaHistories < ActiveRecord::Migration[8.0]
  def change
    create_table :quota_histories do |t|
      t.references :aws_account, null: false, foreign_key: true
      t.references :quota, null: false, foreign_key: { to_table: :quotas }
      t.string :model_name, null: false, limit: 100
      t.bigint :quota_limit, default: 0, null: false
      t.bigint :quota_used, default: 0, null: false
      t.bigint :quota_remaining, default: 0, null: false
      t.json :raw_data  # 历史数据快照
      t.datetime :recorded_at, null: false
      
      t.timestamps
    end
    
    add_index :quota_histories, [:aws_account_id, :model_name, :recorded_at], name: 'idx_quota_hist_account_model_time'
    add_index :quota_histories, :recorded_at
  end
end