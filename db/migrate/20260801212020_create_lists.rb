class CreateLists < ActiveRecord::Migration[8.1]
  def change
    create_table :lists do |t|
      t.belongs_to :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description, null: false
      t.integer :position, null: false, default: 0
      t.boolean :public, null: false, default: true

      t.timestamps
    end

    add_index :lists, "user_id, lower(name)", unique: true, name: "index_lists_on_user_id_and_lower_name"
    add_index :lists, [ :user_id, :slug ], unique: true

    add_check_constraint :lists, "position >= 0", name: "lists_position_non_negative"
  end
end
