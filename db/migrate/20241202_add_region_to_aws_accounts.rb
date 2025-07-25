# frozen_string_literal: true

class AddRegionToAwsAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :aws_accounts, :region, :string, default: 'us-east-1'
    add_index :aws_accounts, :region
  end
end