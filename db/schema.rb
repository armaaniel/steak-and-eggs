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

ActiveRecord::Schema[8.0].define(version: 2025_08_06_171807) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "portfolio_records", force: :cascade do |t|
    t.integer "user_id", null: false
    t.date "date", null: false
    t.decimal "portfolio_value", null: false
    t.index ["user_id", "date"], name: "index_portfolio_records_on_user_id_and_date", unique: true
    t.index ["user_id"], name: "index_portfolio_records_on_user_id"
  end

  create_table "positions", force: :cascade do |t|
    t.string "symbol", null: false
    t.integer "shares", null: false
    t.integer "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.index ["user_id", "symbol"], name: "index_positions_on_user_id_and_symbol", unique: true
    t.index ["user_id"], name: "index_positions_on_user_id"
  end

  create_table "tickers", force: :cascade do |t|
    t.string "symbol", null: false
    t.string "name", null: false
    t.string "ticker_type", null: false
    t.string "exchange", null: false
    t.string "currency", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
  end

  create_table "transactions", force: :cascade do |t|
    t.integer "transaction_type", null: false
    t.decimal "value", null: false
    t.integer "quantity", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "symbol", null: false
    t.index ["user_id"], name: "index_transactions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "password_digest", null: false
    t.decimal "balance", default: "0.0"
    t.string "username", null: false
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "portfolio_records", "users"
  add_foreign_key "positions", "users"
  add_foreign_key "transactions", "users"
end
