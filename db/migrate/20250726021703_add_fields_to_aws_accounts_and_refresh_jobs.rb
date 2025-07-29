class AddFieldsToAwsAccountsAndRefreshJobs < ActiveRecord::Migration[8.0]
  def change
    # Add tags and progress fields to refresh_jobs
    add_column :refresh_jobs, :account_ids, :json
    add_column :refresh_jobs, :progress, :decimal, precision: 5, scale: 2, default: 0.0
    
    # Add tags to aws_accounts
    add_column :aws_accounts, :tags, :json
    
    # Add max_quota to aws_accounts
    add_column :aws_accounts, :max_quota, :bigint, default: 0
  end
end