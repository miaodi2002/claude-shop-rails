# frozen_string_literal: true

class CreateCostSyncLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :cost_sync_logs do |t|
      t.references :aws_account, null: true, foreign_key: { on_delete: :nullify }
      t.integer :status, null: false, default: 0
      t.integer :sync_type, null: false, default: 0
      t.text :error_message
      t.integer :synced_dates_count, default: 0
      t.timestamp :started_at
      t.timestamp :completed_at
      
      t.timestamps
      
      t.index :status, name: 'idx_status'
      t.index :sync_type, name: 'idx_sync_type'
      t.index :created_at, order: :desc, name: 'idx_created_at'
      t.index [:aws_account_id, :status], name: 'idx_account_status'
    end
  end
end