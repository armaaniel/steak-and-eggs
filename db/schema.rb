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

ActiveRecord::Schema[8.0].define(version: 2026_08_27_221100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "ingester_samples", force: :cascade do |t|
    t.datetime "at", null: false
    t.uuid "boot_id", null: false
    t.uuid "connection_id"
    t.string "kind", default: "tick", null: false
    t.string "state", null: false
    t.string "cause"
    t.bigint "frames", default: 0, null: false
    t.bigint "events", default: 0, null: false
    t.integer "symbols"
    t.integer "max_lag_ms"
    t.datetime "last_message_at"
    t.datetime "first_message_at"
    t.jsonb "detail"
    t.bigint "sum_lag_ms"
    t.integer "sampled_events"
    t.index ["at"], name: "index_ingester_samples_on_at"
    t.index ["boot_id", "at"], name: "index_ingester_samples_on_boot_id_and_at"
    t.index ["connection_id", "at"], name: "index_ingester_samples_on_connection_id_and_at"
    t.index ["kind", "at"], name: "index_ingester_samples_on_kind_and_at"
  end

  create_table "load_samples", force: :cascade do |t|
    t.uuid "run_id", null: false
    t.uuid "request_id", null: false
    t.datetime "at", null: false
    t.string "route", null: false
    t.integer "duration", null: false
    t.integer "waiting"
    t.integer "status"
    t.index ["run_id", "at"], name: "index_load_samples_on_run_id_and_at"
  end

  create_table "portfolio_records", force: :cascade do |t|
    t.integer "user_id", null: false
    t.date "date", null: false
    t.decimal "portfolio_value", precision: 17, scale: 4, null: false
    t.index ["user_id", "date"], name: "index_portfolio_records_on_user_id_and_date", unique: true
    t.index ["user_id"], name: "index_portfolio_records_on_user_id"
    t.check_constraint "portfolio_value >= 0::numeric", name: "portfolio_value_non_negative"
  end

  create_table "positions", force: :cascade do |t|
    t.string "symbol", null: false
    t.bigint "shares", null: false
    t.integer "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "average_price", precision: 10, scale: 4, null: false
    t.index ["user_id", "symbol"], name: "index_positions_on_user_id_and_symbol", unique: true
    t.index ["user_id"], name: "index_positions_on_user_id"
    t.check_constraint "average_price > 0::numeric", name: "average_price_positive"
    t.check_constraint "shares > 0", name: "shares_positive"
  end

  create_table "tickers", force: :cascade do |t|
    t.string "symbol", null: false
    t.string "name", null: false
    t.string "ticker_type", null: false
    t.string "exchange", null: false
    t.string "currency", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_tickers_on_name"
    t.index ["symbol"], name: "index_tickers_on_symbol", unique: true
  end

  create_table "traces", force: :cascade do |t|
    t.string "endpoint", null: false
    t.float "duration"
    t.float "db_runtime"
    t.float "view_runtime"
    t.integer "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "controller"
    t.string "action"
    t.json "breakdown"
    t.bigint "user_id"
    t.boolean "synthetic", default: false, null: false
    t.string "source", default: "user", null: false
    t.uuid "run_id"
    t.string "result"
    t.uuid "request_id"
    t.index ["request_id"], name: "index_traces_on_request_id", where: "(request_id IS NOT NULL)"
    t.index ["run_id"], name: "index_traces_on_run_id", where: "(run_id IS NOT NULL)"
    t.index ["source", "created_at"], name: "index_traces_on_source_and_created_at"
  end

  create_table "transactions", force: :cascade do |t|
    t.integer "transaction_type", null: false
    t.decimal "value", precision: 17, scale: 4, null: false
    t.integer "quantity", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "symbol", null: false
    t.decimal "realized_pnl", precision: 17, scale: 4
    t.decimal "market_price", precision: 10, scale: 4, null: false
    t.decimal "average_price", precision: 10, scale: 4
    t.index ["user_id"], name: "index_transactions_on_user_id"
    t.check_constraint "market_price >= 0::numeric", name: "market_price_non_negative"
    t.check_constraint "quantity > 0", name: "quantity_positive"
    t.check_constraint "transaction_type = ANY (ARRAY[0, 1, 2, 3])", name: "valid_transaction_type"
    t.check_constraint "value > 0::numeric", name: "value_positive"
  end

  create_table "users", force: :cascade do |t|
    t.string "password_digest", null: false
    t.decimal "balance", precision: 17, scale: 4, default: "0.0"
    t.string "username", limit: 20, null: false
    t.index "lower((username)::text)", name: "index_users_on_LOWER_username", unique: true
    t.check_constraint "balance >= 0::numeric", name: "balance_non_negative"
  end

  add_foreign_key "portfolio_records", "users"
  add_foreign_key "positions", "users"
  add_foreign_key "transactions", "users"
end
