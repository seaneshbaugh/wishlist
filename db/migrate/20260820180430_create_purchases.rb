class CreatePurchases < ActiveRecord::Migration[8.1]
  def change
    create_table :purchases do |t|
      t.belongs_to :list_item, null: false, foreign_key: true
      t.belongs_to :user, null: false, foreign_key: true
      t.string :purchased_from
      t.text :notes
      t.decimal :price, precision: 10, scale: 2
      t.integer :quantity, null: false, default: 1
      t.datetime :reveal_at, null: false
      t.boolean :anonymous, null: false, default: false
      t.timestamps
    end

    add_index :purchases, [ :list_item_id, :reveal_at ]

    add_check_constraint :purchases, "price IS NULL OR price >= 0", name: "purchases_price_null_or_non_negative"
    add_check_constraint :purchases, "quantity > 0", name: "purchases_quantity_positive"
  end
end
