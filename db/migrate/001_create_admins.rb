class CreateAdmins < ActiveRecord::Migration[8.0]
  def change
    create_table :admins do |t|
      t.string :username, null: false, limit: 50
      t.string :email, null: false, limit: 100
      t.string :password_digest, null: false
      t.integer :failed_login_attempts, default: 0, null: false
      t.datetime :locked_until
      t.datetime :last_login_at
      t.inet :last_login_ip
      t.boolean :active, default: true, null: false
      
      t.timestamps
    end
    
    add_index :admins, :username, unique: true
    add_index :admins, :email, unique: true
    add_index :admins, :active
  end
end