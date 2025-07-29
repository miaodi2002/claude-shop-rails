class RemoveOldQuotaUniqueIndex < ActiveRecord::Migration[8.0]
  def change
    # Remove the old unique index that conflicts with new quota_type support
    remove_index :quotas, name: 'index_quotas_on_aws_account_id_and_service_name'
  end
end