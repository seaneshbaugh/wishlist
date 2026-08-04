class CreateLists < ActiveRecord::Migration[8.1]
  def change
    create_table :lists do |t|
      t.belongs_to :user
      t.string :name, null: false, default: ""
      t.string :slug, null: false
      t.string :description, null: false, default: ""
      t.integer :order, null: false, default: 0
      t.boolean :public, null: false, default: true

      t.timestamps
    end

    add_index :lists, "user_id, lower(name)", unique: true, name: "index_lists_on_user_id_and_lower_name"
    add_index :lists, [ :user_id, :slug ], unique: true
  end
end
