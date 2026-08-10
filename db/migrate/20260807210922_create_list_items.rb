class CreateListItems < ActiveRecord::Migration[8.1]
  def change
    create_table :list_items do |t|
      t.belongs_to :list, null: false, foreign_key: true
      t.string :name, null: false
      t.text :notes
      t.string :url
      t.decimal :price, precision: 10, scale: 2
      t.integer :quantity, null: false, default: 1
      t.integer :priority, null: false, default: 2
      t.integer :position, null: false, default: 0
      t.boolean :visible, null: false, default: true

      t.timestamps
    end

    add_index :list_items, [ :list_id, :priority, :position ]

    add_check_constraint :list_items, "price >= 0", name: "list_items_price_non_negative"
    add_check_constraint :list_items, "quantity > 0", name: "list_items_quantity_positive"
    add_check_constraint :list_items, "priority BETWEEN 0 AND 4", name: "list_items_priority_valid"
    add_check_constraint :list_items, "position >= 0", name: "list_items_position_non_negative"
  end
end
