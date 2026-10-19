require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @user = users(:sean)
    @outgoing_friend = users(:casie)
    @incoming_friend = users(:amelia)
  end

  test "accepted friends are mutual regardless of request direction" do
    connect(@user, @outgoing_friend)
    connect(@incoming_friend, @user)

    assert_equal [ @outgoing_friend.id, @incoming_friend.id ].sort, @user.friends.ids.sort
    assert_equal [ @user.id ], @outgoing_friend.friends.ids
    assert_equal [ @user.id ], @incoming_friend.friends.ids
  end

  test "pending requests are not friends in either direction" do
    Friendship.create!(requester: @user, recipient: @outgoing_friend)
    Friendship.create!(requester: @incoming_friend, recipient: @user)

    assert_empty @user.friends
    assert_empty @outgoing_friend.friends
    assert_empty @incoming_friend.friends
  end

  test "friendship is not transitive" do
    connect(@user, @outgoing_friend)
    connect(@outgoing_friend, @incoming_friend)

    assert_not_includes @user.friends, @incoming_friend
    assert_not_includes @incoming_friend.friends, @user
  end

  test "friends is a chainable relation" do
    connect(@user, @outgoing_friend)
    connect(@incoming_friend, @user)

    assert_kind_of ActiveRecord::Relation, @user.friends
    assert_equal [ @incoming_friend.id, @outgoing_friend.id ], @user.friends.alphabetical.ids
    assert_equal [ @outgoing_friend.id ], @user.friends.where(username: @outgoing_friend.username).ids
  end

  test "acceptance and removal are reflected in fresh friend queries" do
    friendship = Friendship.create!(requester: @user, recipient: @outgoing_friend)

    assert_empty @user.friends

    friendship.update!(accepted_at: Time.current)

    assert_equal [ @outgoing_friend.id ], @user.friends.ids

    friendship.destroy!

    assert_empty @user.friends
    assert_empty @outgoing_friend.friends
  end

  test "deleting a user removes incoming and outgoing friendships in either state" do
    pending = Friendship.create!(requester: @outgoing_friend, recipient: @user)
    accepted = connect(@user, @incoming_friend)

    assert_difference "Friendship.count", -2 do
      @user.destroy!
    end

    assert_not Friendship.exists?(pending.id)
    assert_not Friendship.exists?(accepted.id)
    assert User.exists?(@outgoing_friend.id)
    assert User.exists?(@incoming_friend.id)
  end

  test "a user without friendships has no friends" do
    assert_empty @user.friends
    assert_empty User.new.friends
  end

  private

  def connect(requester, recipient)
    Friendship.create!(requester: requester, recipient: recipient, accepted_at: Time.current)
  end
end
