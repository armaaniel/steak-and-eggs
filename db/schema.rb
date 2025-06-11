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

ActiveRecord::Schema[8.0].define(version: 2025_06_10_233324) do
  create_table "positions", force: :cascade do |t|
    t.string "symbol", null: false
    t.integer "shares", null: false
    t.integer "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_positions_on_user_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.integer "transaction_type", null: false
    t.decimal "amount", null: false
    t.integer "quantity", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "symbol", null: false
    t.index ["user_id"], name: "index_transactions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.decimal "balance", default: "0.0"
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.date "date_of_birth", null: false
    t.integer "gender", null: false
    t.string "middle_name"
    t.decimal "used_margin", default: "0.0", null: false
    t.string "margin_call_status"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "positions", "users"
  add_foreign_key "transactions", "users"
end
