class CreateInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :invitations do |t|
      t.references :inviter, null: false, foreign_key: { to_table: :users }
      t.string :email, null: false
      t.references :invitee, foreign_key: { to_table: :users }
      t.datetime :accepted_at

      t.timestamps
    end

    add_index :invitations, "inviter_id, lower(email)", unique: true,
              where: "accepted_at IS NULL", name: "index_invitations_on_pending_inviter_email"
    add_check_constraint :invitations,
                         "(invitee_id IS NULL) = (accepted_at IS NULL)",
                         name: "invitations_acceptance_consistent"
    add_check_constraint :invitations, "inviter_id <> invitee_id",
                         name: "invitations_different_users"
  end
end
