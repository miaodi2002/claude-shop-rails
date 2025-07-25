class CreateSystemConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :system_configs do |t|
      t.string :key, null: false, limit: 100
      t.text :value
      t.string :data_type, default: 'string', null: false  # string, integer, boolean, json
      t.text :description
      t.boolean :editable, default: true, null: false
      t.boolean :encrypted, default: false, null: false
      
      t.timestamps
    end
    
    add_index :system_configs, :key, unique: true
    add_index :system_configs, :editable
  end
end