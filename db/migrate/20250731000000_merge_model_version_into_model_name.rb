# frozen_string_literal: true

class MergeModelVersionIntoModelName < ActiveRecord::Migration[8.0]
  def up
    # 更新所有有版本信息的记录，将版本合并到模型名称中
    QuotaDefinition.where.not(model_version: [nil, '']).find_each do |quota|
      new_name = "#{quota.claude_model_name} #{quota.model_version}"
      quota.update_column(:claude_model_name, new_name)
    end
    
    # 删除 model_version 字段
    remove_column :quota_definitions, :model_version
  end
  
  def down
    # 添加回 model_version 字段
    add_column :quota_definitions, :model_version, :string
    
    # 尝试从 claude_model_name 中提取版本信息
    QuotaDefinition.find_each do |quota|
      if quota.claude_model_name =~ /(.+)\s+(V\d+)$/
        quota.update_columns(
          claude_model_name: $1,
          model_version: $2
        )
      end
    end
  end
end