require "test_helper"

class InvitationTest < ActiveSupport::TestCase
  setup do
    @inviter = users(:sean)
    @invitee = users(:casie)
  end

  test "pending invitation normalizes email without creating a user" do
    invitation = nil

    assert_no_difference "User.count" do
      invitation = create_invitation(email: "  NEW@Example.com \t")
    end

    assert_equal "new@example.com", invitation.email
    assert_nil invitation.invitee
    assert_nil invitation.accepted_at
    assert_includes @inviter.sent_invitations, invitation
    assert_includes Invitation.pending, invitation
    assert_not_includes Invitation.accepted, invitation
  end

  test "acceptance associates the recipient and changes scopes" do
    invitation = create_invitation

    invitation.update!(invitee: @invitee, accepted_at: Time.current)

    assert_includes @invitee.accepted_invitations, invitation
    assert_includes Invitation.accepted, invitation
    assert_not_includes Invitation.pending, invitation
    assert invitation.valid?, invitation.errors.full_messages.to_sentence
  end

  test "inviter and valid email are required" do
    invitation = Invitation.new

    assert_not invitation.valid?
    assert invitation.errors.of_kind?(:inviter, :blank)
    assert invitation.errors.of_kind?(:email, :blank)

    invitation.email = "invalid"

    assert_not invitation.valid?
    assert invitation.errors.of_kind?(:email, :invalid)
  end

  test "one pending invitation per inviter and normalized email" do
    invitation = create_invitation
    duplicate = @inviter.sent_invitations.build(email: " NEW@EXAMPLE.COM ")

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:email, :taken)
    assert invitation.valid?

    assert create_invitation(inviter: users(:amelia)).persisted?

    invitation.update!(invitee: @invitee, accepted_at: Time.current)

    assert create_invitation.persisted?
    assert invitation.reload.valid?
  end

  test "acceptance requires both recipient and timestamp" do
    [ { invitee: @invitee }, { accepted_at: Time.current } ].each do |attributes|
      invitation = Invitation.new({ inviter: @inviter, email: @invitee.email }.merge(attributes))

      assert_not invitation.valid?

      if attributes.key?(:invitee)
        assert invitation.errors.of_kind?(:accepted_at, :blank)
      else
        assert invitation.errors.of_kind?(:invitee, :blank)
      end
    end
  end

  test "cannot invite own email or accept own invitation" do
    invitation = @inviter.sent_invitations.build(email: " #{@inviter.email.upcase} ")

    assert_not invitation.valid?
    assert invitation.errors.of_kind?(:email, :same_as_inviter)

    invitation.assign_attributes(email: "other@example.com", invitee: @inviter, accepted_at: Time.current)

    assert_not invitation.valid?
    assert invitation.errors.of_kind?(:invitee, :same_as_inviter)
  end

  test "cancellation permits reinviting with a new identity" do
    invitation = create_invitation

    invitation.destroy!

    assert_not_equal invitation.id, create_invitation.id
  end

  test "accepted friends cannot receive pending invitations in either direction" do
    [ [ @inviter, @invitee ], [ @invitee, @inviter ] ].each do |requester, recipient|
      friendship = Friendship.create!(requester: requester, recipient: recipient, accepted_at: Time.current)
      invitation = @inviter.sent_invitations.build(email: @invitee.email)

      assert_not invitation.valid?
      assert invitation.errors.of_kind?(:email, :already_friends)

      invitation.assign_attributes(invitee: @invitee, accepted_at: Time.current)

      assert invitation.valid?, invitation.errors.full_messages.to_sentence

      friendship.destroy!
    end
  end

  test "pending friend requests do not prevent invitations" do
    Friendship.create!(requester: @inviter, recipient: @invitee)

    assert create_invitation(email: @invitee.email).persisted?
  end

  test "deleting inviter removes pending and accepted invitations without deleting invitee" do
    pending = create_invitation
    accepted = create_invitation(email: @invitee.email, invitee: @invitee, accepted_at: Time.current)

    @inviter.destroy!

    assert_not Invitation.exists?(pending.id)
    assert_not Invitation.exists?(accepted.id)
    assert User.exists?(@invitee.id)
  end

  test "deleting invitee removes accepted invitations without deleting inviter or other invitations" do
    accepted = create_invitation(email: @invitee.email, invitee: @invitee, accepted_at: Time.current)
    pending = create_invitation

    @invitee.destroy!

    assert_not Invitation.exists?(accepted.id)
    assert Invitation.exists?(pending.id)
    assert User.exists?(@inviter.id)
  end

  test "database enforces case insensitive pending uniqueness but allows other inviters and accepted history" do
    create_invitation

    assert_raises ActiveRecord::RecordNotUnique do
      insert_without_validation(email: "NEW@EXAMPLE.COM")
    end

    insert_without_validation(inviter_id: users(:amelia).id)
    2.times { insert_without_validation(invitee_id: @invitee.id, accepted_at: Time.current) }
  end

  test "database rejects inconsistent acceptance and self acceptance" do
    [ { invitee_id: @invitee.id }, { accepted_at: Time.current },
      { invitee_id: @inviter.id, accepted_at: Time.current } ].each do |attributes|
      error = assert_raises ActiveRecord::StatementInvalid do
        insert_without_validation(**attributes)
      end

      assert_kind_of PG::CheckViolation, error.cause
    end
  end

  test "database requires inviter and email and enforces both user foreign keys" do
    [ { inviter_id: nil }, { email: nil } ].each do |attributes|
      assert_raises(ActiveRecord::NotNullViolation) { insert_without_validation(**attributes) }
    end

    missing_id = User.maximum(:id) + 1

    [ { inviter_id: missing_id }, { invitee_id: missing_id, accepted_at: Time.current } ].each do |attributes|
      assert_raises(ActiveRecord::InvalidForeignKey) { insert_without_validation(**attributes) }
    end
  end

  private

  def create_invitation(**attributes)
    Invitation.create!({ inviter: @inviter, email: "new@example.com" }.merge(attributes))
  end

  def insert_without_validation(**attributes)
    Invitation.transaction(requires_new: true) do
      Invitation.insert_all!([ { inviter_id: @inviter.id, email: "new@example.com" }.merge(attributes) ])
    end
  end
end
