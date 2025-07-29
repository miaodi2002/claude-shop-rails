# frozen_string_literal: true

class RenameModelNameInQuotaDefinitions < ActiveRecord::Migration[8.0]
  def change
    rename_column :quota_definitions, :model_name, :claude_model_name
  end
end