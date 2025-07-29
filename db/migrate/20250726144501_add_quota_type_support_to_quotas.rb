class AddQuotaTypeSupportToQuotas < ActiveRecord::Migration[8.0]
  def change
    add_column :quotas, :quota_type, :string, null: false, default: 'requests_per_minute'
    add_column :quotas, :aws_quota_code, :string
    add_column :quotas, :default_value, :decimal, precision: 15, scale: 2
    add_column :quotas, :is_adjustable, :boolean, default: false
    add_column :quotas, :quota_level, :string

    add_index :quotas, :quota_type
    add_index :quotas, :aws_quota_code
    add_index :quotas, :quota_level
    add_index :quotas, [:aws_account_id, :service_name, :quota_type], 
              unique: true, 
              name: 'index_quotas_on_account_service_type'
  end
end