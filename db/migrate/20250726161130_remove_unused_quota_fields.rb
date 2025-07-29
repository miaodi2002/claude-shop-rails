class RemoveUnusedQuotaFields < ActiveRecord::Migration[8.0]
  def change
    # Remove quota_used and quota_remaining fields as they are no longer needed
    # We only need quota_limit and default_value for the simplified quota logic
    remove_column :quotas, :quota_used, :bigint
    remove_column :quotas, :quota_remaining, :bigint
  end
end