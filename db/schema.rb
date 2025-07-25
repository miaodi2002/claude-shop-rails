# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2025_07_25_052035) do

  create_table "admins", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.string "username", limit: 50, null: false
    t.string "email", limit: 100, null: false
    t.string "password_digest", null: false
    t.integer "failed_login_attempts", default: 0, null: false
    t.datetime "locked_until"
    t.datetime "last_login_at"
    t.string "last_login_ip", limit: 45
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "full_name", limit: 100
    t.integer "role", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "password_changed_at"
    t.index ["email"], name: "index_admins_on_email", unique: true
    t.index ["role"], name: "index_admins_on_role"
    t.index ["status"], name: "index_admins_on_status"
    t.index ["username"], name: "index_admins_on_username", unique: true
  end

  create_table "audit_logs", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.bigint "admin_id"
    t.string "action", limit: 50, null: false
    t.string "target_type", limit: 50
    t.bigint "target_id"
    t.json "changes"
    t.json "metadata"
    t.string "ip_address", limit: 45
    t.text "user_agent"
    t.boolean "successful", default: true, null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["admin_id"], name: "index_audit_logs_on_admin_id"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["successful"], name: "index_audit_logs_on_successful"
    t.index ["target_type", "target_id"], name: "index_audit_logs_on_target_type_and_target_id"
  end

  create_table "aws_accounts", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.string "account_id", limit: 20, null: false
    t.string "access_key", limit: 100, null: false
    t.text "secret_key_encrypted", null: false
    t.string "secret_key_encrypted_iv", null: false
    t.string "name", limit: 100, null: false
    t.text "description"
    t.integer "status", default: 0, null: false
    t.integer "connection_status", default: 2, null: false
    t.text "connection_error_message"
    t.datetime "last_connection_test_at"
    t.datetime "last_quota_update_at"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_aws_accounts_on_account_id", unique: true
    t.index ["connection_status"], name: "index_aws_accounts_on_connection_status"
    t.index ["deleted_at"], name: "index_aws_accounts_on_deleted_at"
    t.index ["status"], name: "index_aws_accounts_on_status"
  end

  create_table "quota_histories", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.bigint "aws_account_id", null: false
    t.bigint "quota_id", null: false
    t.string "model_name", limit: 100, null: false
    t.bigint "quota_limit", default: 0, null: false
    t.bigint "quota_used", default: 0, null: false
    t.bigint "quota_remaining", default: 0, null: false
    t.json "raw_data"
    t.datetime "recorded_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["aws_account_id", "model_name", "recorded_at"], name: "idx_quota_hist_account_model_time"
    t.index ["aws_account_id"], name: "index_quota_histories_on_aws_account_id"
    t.index ["quota_id"], name: "index_quota_histories_on_quota_id"
    t.index ["recorded_at"], name: "index_quota_histories_on_recorded_at"
  end

  create_table "quotas", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.bigint "aws_account_id", null: false
    t.string "model_name", limit: 100, null: false
    t.bigint "quota_limit", default: 0, null: false
    t.bigint "quota_used", default: 0, null: false
    t.bigint "quota_remaining", default: 0, null: false
    t.datetime "last_updated_at"
    t.integer "update_status", default: 2, null: false
    t.text "update_error_message"
    t.json "raw_data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["aws_account_id", "model_name"], name: "index_quotas_on_aws_account_id_and_model_name", unique: true
    t.index ["aws_account_id"], name: "index_quotas_on_aws_account_id"
    t.index ["last_updated_at"], name: "index_quotas_on_last_updated_at"
    t.index ["model_name"], name: "index_quotas_on_model_name"
    t.index ["update_status"], name: "index_quotas_on_update_status"
  end

  create_table "refresh_jobs", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.bigint "aws_account_id"
    t.string "job_type", limit: 50, null: false
    t.integer "status", default: 0, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.integer "total_accounts", default: 0
    t.integer "processed_accounts", default: 0
    t.integer "successful_accounts", default: 0
    t.integer "failed_accounts", default: 0
    t.json "results"
    t.text "error_message"
    t.bigint "admin_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_id"], name: "index_refresh_jobs_on_admin_id"
    t.index ["aws_account_id"], name: "index_refresh_jobs_on_aws_account_id"
    t.index ["created_at"], name: "index_refresh_jobs_on_created_at"
    t.index ["job_type"], name: "index_refresh_jobs_on_job_type"
    t.index ["status"], name: "index_refresh_jobs_on_status"
  end

  create_table "system_configs", options: "ENGINE=InnoDB DEFAULT CHARSET=utf8", force: :cascade do |t|
    t.string "key", limit: 100, null: false
    t.text "value"
    t.string "data_type", default: "string", null: false
    t.text "description"
    t.boolean "editable", default: true, null: false
    t.boolean "encrypted", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["editable"], name: "index_system_configs_on_editable"
    t.index ["key"], name: "index_system_configs_on_key", unique: true
  end

  add_foreign_key "audit_logs", "admins"
  add_foreign_key "quota_histories", "aws_accounts"
  add_foreign_key "quota_histories", "quotas"
  add_foreign_key "quotas", "aws_accounts"
  add_foreign_key "refresh_jobs", "admins"
  add_foreign_key "refresh_jobs", "aws_accounts"
end
