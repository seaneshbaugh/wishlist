require "test_helper"

class FriendshipTest < ActiveSupport::TestCase
  setup do
    @requester = users(:sean)
    @recipient = users(:casie)
  end

  test "new friendship is pending and belongs to both participants" do
    friendship = create_friendship

    assert_nil friendship.accepted_at
    assert_equal @requester, friendship.requester
    assert_equal @recipient, friendship.recipient
    assert_includes Friendship.pending, friendship
    assert_not_includes Friendship.accepted, friendship
    assert_includes @requester.outgoing_friendships, friendship
    assert_includes @recipient.incoming_friendships, friendship
  end

  test "acceptance moves a friendship from pending to accepted" do
    friendship = create_friendship
    friendship.update!(accepted_at: Time.current)

    assert_includes Friendship.accepted, friendship
    assert_not_includes Friendship.pending, friendship
  end

  test "both participants are required" do
    friendship = Friendship.new

    assert_not friendship.valid?
    assert friendship.errors.of_kind?(:requester, :blank)
    assert friendship.errors.of_kind?(:recipient, :blank)
  end

  test "self friendship is invalid" do
    friendship = Friendship.new(requester: @requester, recipient: @requester)

    assert_not friendship.valid?
    assert friendship.errors.of_kind?(:recipient, :same_as_requester)
  end

  [ nil, Time.utc(2026, 1, 1) ].each do |accepted_at|
    test "existing pair with acceptance #{accepted_at.inspect} rejects duplicates in either direction" do
      create_friendship(accepted_at: accepted_at)

      [ [ @requester, @recipient ], [ @recipient, @requester ] ].each do |requester, recipient|
        duplicate = Friendship.new(requester: requester, recipient: recipient)

        assert_not duplicate.valid?
        assert duplicate.errors.of_kind?(:base, :already_exists)
      end
    end
  end

  test "an existing friendship does not match itself during validation" do
    friendship = create_friendship

    assert friendship.valid?, friendship.errors.full_messages.to_sentence
    assert friendship.update(accepted_at: Time.current)
  end

  test "different pairs can share a participant" do
    create_friendship

    other = Friendship.new(requester: @requester, recipient: users(:amelia))

    assert other.save, other.errors.full_messages.to_sentence
  end

  test "deleting a friendship allows a new request in the opposite direction" do
    create_friendship.destroy!

    replacement = Friendship.new(requester: @recipient, recipient: @requester)

    assert replacement.save, replacement.errors.full_messages.to_sentence
  end

  test "database rejects self friendship without model validation" do
    error = assert_raises ActiveRecord::StatementInvalid do
      Friendship.transaction(requires_new: true) do
        Friendship.insert_all!([ { requester_id: @requester.id, recipient_id: @requester.id } ])
      end
    end

    assert_kind_of PG::CheckViolation, error.cause
    assert_empty Friendship.all
  end

  test "database rejects duplicate pairs in either direction without model validation" do
    friendship = create_friendship

    [ [ @requester.id, @recipient.id ], [ @recipient.id, @requester.id ] ].each do |requester_id, recipient_id|
      assert_raises ActiveRecord::RecordNotUnique do
        Friendship.transaction(requires_new: true) do
          Friendship.insert_all!([ { requester_id: requester_id, recipient_id: recipient_id, accepted_at: Time.current } ])
        end
      end
    end

    assert_equal [ friendship.id ], Friendship.ids
  end

  test "database requires participants and enforces user foreign keys" do
    assert_raises ActiveRecord::NotNullViolation do
      Friendship.transaction(requires_new: true) do
        Friendship.insert_all!([ { requester_id: @requester.id, recipient_id: nil } ])
      end
    end

    missing_user_id = User.maximum(:id) + 1

    assert_raises ActiveRecord::InvalidForeignKey do
      Friendship.transaction(requires_new: true) do
        Friendship.insert_all!([ { requester_id: @requester.id, recipient_id: missing_user_id } ])
      end
    end
  end

  private

  def create_friendship(**attributes)
    Friendship.create!({ requester: @requester, recipient: @recipient }.merge(attributes))
  end
end
