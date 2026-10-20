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
end
