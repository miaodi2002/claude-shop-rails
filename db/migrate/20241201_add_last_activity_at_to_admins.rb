# frozen_string_literal: true

class AddLastActivityAtToAdmins < ActiveRecord::Migration[8.0]
  def change
    add_column :admins, :last_activity_at, :datetime
    add_index :admins, :last_activity_at
  end
end