class CreateFriendships < ActiveRecord::Migration[8.1]
  def change
    create_table :friendships do |t|
      t.references :requester, null: false, foreign_key: { to_table: :users }
      t.references :recipient, null: false, foreign_key: { to_table: :users }
      t.datetime :accepted_at

      t.timestamps
    end

    add_check_constraint :friendships, "requester_id <> recipient_id", name: "friendships_different_users"
    add_index :friendships,
              "LEAST(requester_id, recipient_id), GREATEST(requester_id, recipient_id)",
              unique: true, name: "index_friendships_on_user_pair"
  end
end
