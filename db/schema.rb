# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_08_26_144700) do
  create_table "account_quotas", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "aws_account_id", null: false
    t.bigint "quota_definition_id", null: false
    t.decimal "current_quota", precision: 15, scale: 2, default: "0.0"
    t.string "quota_level", default: "unknown"
    t.boolean "is_adjustable", default: false
    t.datetime "last_sync_at"
    t.string "sync_status", default: "pending"
    t.text "sync_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["aws_account_id", "quota_definition_id"], name: "idx_account_quota_unique", unique: true
    t.index ["aws_account_id"], name: "index_account_quotas_on_aws_account_id"
    t.index ["quota_definition_id"], name: "index_account_quotas_on_quota_definition_id"
    t.index ["quota_level"], name: "index_account_quotas_on_quota_level"
    t.index ["sync_status"], name: "index_account_quotas_on_sync_status"
  end

  create_table "admins", charset: "utf8mb3", force: :cascade do |t|
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
    t.datetime "last_activity_at"
    t.index ["email"], name: "index_admins_on_email", unique: true
    t.index ["last_activity_at"], name: "index_admins_on_last_activity_at"
    t.index ["role"], name: "index_admins_on_role"
    t.index ["status"], name: "index_admins_on_status"
    t.index ["username"], name: "index_admins_on_username", unique: true
  end

  create_table "audit_logs", charset: "utf8mb3", force: :cascade do |t|
    t.bigint "admin_id"
    t.string "action", limit: 50, null: false
    t.string "target_type", limit: 50
    t.bigint "target_id"
    t.json "change_details"
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

  create_table "aws_accounts", charset: "utf8mb3", force: :cascade do |t|
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
    t.string "region", default: "us-east-1"
    t.json "tags"
    t.index ["account_id"], name: "index_aws_accounts_on_account_id", unique: true
    t.index ["connection_status"], name: "index_aws_accounts_on_connection_status"
    t.index ["deleted_at"], name: "index_aws_accounts_on_deleted_at"
    t.index ["region"], name: "index_aws_accounts_on_region"
    t.index ["status"], name: "index_aws_accounts_on_status"
  end

  create_table "cost_sync_logs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "aws_account_id"
    t.integer "status", default: 0, null: false
    t.integer "sync_type", default: 0, null: false
    t.text "error_message"
    t.integer "synced_dates_count", default: 0
    t.timestamp "started_at"
    t.timestamp "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["aws_account_id", "status"], name: "idx_account_status"
    t.index ["aws_account_id"], name: "index_cost_sync_logs_on_aws_account_id"
    t.index ["created_at"], name: "idx_created_at", order: :desc
    t.index ["status"], name: "idx_status"
    t.index ["sync_type"], name: "idx_sync_type"
  end

  create_table "daily_costs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "aws_account_id", null: false
    t.date "date", null: false
    t.decimal "cost_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.string "currency", limit: 3, default: "USD", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["aws_account_id", "date"], name: "idx_account_date"
    t.index ["aws_account_id", "date"], name: "idx_recent_costs", order: { date: :desc }
    t.index ["aws_account_id", "date"], name: "unique_account_date", unique: true
    t.index ["aws_account_id"], name: "index_daily_costs_on_aws_account_id"
    t.index ["date"], name: "idx_date"
  end

  create_table "quota_definitions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "quota_code", null: false
    t.string "claude_model_name", null: false
    t.string "quota_type", null: false
    t.text "quota_name", null: false
    t.string "call_type"
    t.decimal "default_value", precision: 15, scale: 2
    t.boolean "is_active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["claude_model_name", "quota_type"], name: "index_quota_definitions_on_claude_model_name_and_quota_type"
    t.index ["is_active"], name: "index_quota_definitions_on_is_active"
    t.index ["quota_code"], name: "index_quota_definitions_on_quota_code", unique: true
  end

  create_table "refresh_jobs", charset: "utf8mb3", force: :cascade do |t|
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
    t.json "account_ids"
    t.decimal "progress", precision: 5, scale: 2, default: "0.0"
    t.index ["admin_id"], name: "index_refresh_jobs_on_admin_id"
    t.index ["aws_account_id"], name: "index_refresh_jobs_on_aws_account_id"
    t.index ["created_at"], name: "index_refresh_jobs_on_created_at"
    t.index ["job_type"], name: "index_refresh_jobs_on_job_type"
    t.index ["status"], name: "index_refresh_jobs_on_status"
  end

  create_table "system_configs", charset: "utf8mb3", force: :cascade do |t|
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

  add_foreign_key "account_quotas", "aws_accounts"
  add_foreign_key "account_quotas", "quota_definitions"
  add_foreign_key "audit_logs", "admins"
  add_foreign_key "cost_sync_logs", "aws_accounts", on_delete: :nullify
  add_foreign_key "daily_costs", "aws_accounts", on_delete: :cascade
  add_foreign_key "refresh_jobs", "admins"
  add_foreign_key "refresh_jobs", "aws_accounts"
end
