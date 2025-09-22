# frozen_string_literal: true

class CreateDailyCosts < ActiveRecord::Migration[8.0]
  def change
    create_table :daily_costs do |t|
      t.references :aws_account, null: false, foreign_key: { on_delete: :cascade }
      t.date :date, null: false
      t.decimal :cost_amount, precision: 10, scale: 2, null: false, default: 0.00
      t.string :currency, limit: 3, null: false, default: 'USD'
      
      t.timestamps
      
      t.index [:aws_account_id, :date], unique: true, name: 'unique_account_date'
      t.index :date, name: 'idx_date'
      t.index [:aws_account_id, :date], name: 'idx_account_date'
      t.index [:aws_account_id, :date], order: { date: :desc }, name: 'idx_recent_costs'
    end
  end
end