class AddTagsToAwsAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :aws_accounts, :tags, :json
  end
end
