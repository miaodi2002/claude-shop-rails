class CreateRefreshJobs < ActiveRecord::Migration[5.2]
  def change
    create_table :refresh_jobs do |t|
      t.references :aws_account, null: true, foreign_key: true  # null for batch jobs
      t.string :job_type, null: false, limit: 50  # manual, automatic, scheduled
      t.integer :status, default: 0, null: false  # 0: pending, 1: running, 2: completed, 3: failed
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :total_accounts, default: 0
      t.integer :processed_accounts, default: 0
      t.integer :successful_accounts, default: 0
      t.integer :failed_accounts, default: 0
      t.json :results  # 详细结果
      t.text :error_message
      t.references :admin, null: true, foreign_key: true  # who triggered the job
      
      t.timestamps
    end
    
    add_index :refresh_jobs, :status
    add_index :refresh_jobs, :job_type
    add_index :refresh_jobs, :created_at
  end
end