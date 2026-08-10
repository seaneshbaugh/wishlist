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

ActiveRecord::Schema[8.1].define(version: 2026_08_07_210922) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "friendly_id_slugs", force: :cascade do |t|
    t.datetime "created_at"
    t.string "scope"
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_type", "sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_type_and_sluggable_id"
  end

  create_table "list_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "list_id", null: false
    t.string "name", null: false
    t.text "notes"
    t.integer "position", default: 0, null: false
    t.decimal "price", precision: 10, scale: 2
    t.integer "priority", default: 2, null: false
    t.integer "quantity", default: 1, null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.boolean "visible", default: true, null: false
    t.index ["list_id", "priority", "position"], name: "index_list_items_on_list_id_and_priority_and_position"
    t.index ["list_id"], name: "index_list_items_on_list_id"
    t.check_constraint "\"position\" >= 0", name: "list_items_position_non_negative"
    t.check_constraint "price >= 0::numeric", name: "list_items_price_non_negative"
    t.check_constraint "priority >= 0 AND priority <= 4", name: "list_items_priority_valid"
    t.check_constraint "quantity > 0", name: "list_items_quantity_positive"
  end

  create_table "lists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.boolean "public", default: true, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index "user_id, lower((name)::text)", name: "index_lists_on_user_id_and_lower_name", unique: true
    t.index ["user_id", "slug"], name: "index_lists_on_user_id_and_slug", unique: true
    t.index ["user_id"], name: "index_lists_on_user_id"
    t.check_constraint "\"position\" >= 0", name: "lists_position_non_negative"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "locked_at"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index "lower((username)::text)", name: "index_users_on_lower_username", unique: true
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
    t.check_constraint "username::text ~ '^[A-Za-z][A-Za-z0-9_]{3,31}$'::text", name: "users_username_format"
  end

  add_foreign_key "list_items", "lists"
  add_foreign_key "lists", "users"
end
