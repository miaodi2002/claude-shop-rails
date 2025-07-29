class RenameModelNameToServiceInQuotas < ActiveRecord::Migration[8.0]
  def change
    rename_column :quotas, :model_name, :service_name
    rename_column :quota_histories, :model_name, :service_name
  end
end
