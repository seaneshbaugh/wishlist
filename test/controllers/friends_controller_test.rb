require "test_helper"

class FriendsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:sean)
    @friend = users(:casie)
    @stranger = users(:amelia)
    confirm_and_sign_in @user
  end

  test "index shows accepted friends with visible list counts and excludes pending users" do
    Friendship.create!(requester: @friend, recipient: @user, accepted_at: Time.current)
    Friendship.create!(requester: @user, recipient: @stranger)
    @friend.lists.create!(name: "Shared list", description: "")
    @friend.lists.create!(name: "Private list", description: "", public: false)

    get friends_path

    assert_response :success
    assert_select "a[href='#{friend_lists_path(@friend)}']", text: @friend.username
    assert_select "span", text: "1 list"
    assert_select "a[href='#{friend_lists_path(@stranger)}']", count: 0
  end

  test "self and unrelated profiles or lists are inaccessible" do
    [ @user, @friend, @stranger ].each do |user|
      confirm_and_sign_in @user

      get friend_lists_path(user)

      assert_response :not_found
    end

    get "/friends/#{@user.username}"

    assert_response :not_found
  end

  test "friend with no lists is still shown" do
    Friendship.create!(requester: @user, recipient: @friend, accepted_at: Time.current)

    get friends_path

    assert_select "a[href='#{friend_lists_path(@friend)}']", text: @friend.username
    assert_select "span", text: "0 lists"
  end

  test "legacy user directory and nested routes no longer exist" do
    get "/users"

    assert_response :not_found

    get "/users/#{@friend.username}/lists"

    assert_response :not_found
  end

  test "pending friendship does not grant direct list access" do
    Friendship.create!(requester: @user, recipient: @friend)

    confirm_and_sign_in @friend

    get friend_list_path(@user, lists(:christmas_list))

    assert_response :not_found
  end

  test "friends index query count stays constant as accepted friends and lists are added" do
    Friendship.create!(requester: @friend, recipient: @user, accepted_at: Time.current)

    get friends_path

    before = index_select_count

    4.times do |number|
      friend = User.create!(username: "newfriend#{number}", email: "newfriend#{number}@example.com", password: "password123")

      if number.even?
        Friendship.create!(requester: @user, recipient: friend, accepted_at: Time.current)
      else
        Friendship.create!(requester: friend, recipient: @user, accepted_at: Time.current)
      end

      friend.lists.create!(name: "Shared wishlist", description: "") unless number.zero?
      friend.lists.create!(name: "Private wishlist", description: "", public: false)
    end

    assert_equal before, index_select_count
    assert_select "#friends a[href='#{friend_lists_path(@friend)}']", count: 1
    assert_select "#friends span", text: "0 lists", count: 2
    assert_select "#friends span", text: "1 list", count: 3
  end

  test "anonymous visitors cannot browse the friends index" do
    sign_out @user
    get friends_path
    assert_response :not_found
  end

  %w[unrelated incoming_pending outgoing_pending].each do |state|
    test "#{state} user cannot access lists or purchases even with purchase history" do
      case state
      when "incoming_pending"
        Friendship.create!(requester: @user, recipient: @friend)
      when "outgoing_pending"
        Friendship.create!(requester: @friend, recipient: @user)
      end

      list = lists(:christmas_list)
      item = list_items(:paint_brush)
      historical = item.purchases.create!(user: @friend, quantity: 1, reveal_at: 1.day.ago)
      current = item.purchases.create!(user: @friend, quantity: 1, reveal_at: 1.day.from_now)

      [ friend_lists_path(@user), friend_list_path(@user, list) ].each do |path|
        confirm_and_sign_in @friend
        get path
        assert_response :not_found
      end

      assert_no_difference "Purchase.count" do
        confirm_and_sign_in @friend

        post friend_list_purchases_path(@user, list), params: { purchase: { list_item_id: item.id, quantity: 1, reveal_at: 1.day.from_now } }

        assert_response :not_found

        confirm_and_sign_in @friend

        patch friend_list_purchase_path(@user, list, current), params: { purchase: { notes: "Unauthorized" } }

        assert_response :not_found

        confirm_and_sign_in @friend

        delete friend_list_purchase_path(@user, list, current)

        assert_response :not_found
      end

      assert_nil current.reload.notes
      assert historical.reload.revealed?
    end
  end

  private

  def index_select_count
    queries = []
    subscriber = lambda do |*, payload|
      queries << payload[:sql] if payload[:sql].match?(/\ASELECT/i) && payload[:name] != "SCHEMA"
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      get friends_path
    end

    assert_response :success

    queries.size
  end
end
