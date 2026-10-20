require "application_system_test_case"

class FriendshipsTest < ApplicationSystemTestCase
  setup do
    @requester = users(:sean)
    @recipient = users(:casie)
    @requester.confirm
    @recipient.confirm
    confirm_and_sign_in @requester
  end

  test "request acceptance browsing and removal work through the interface" do
    visit friends_path

    fill_in "Friend's email address", with: @recipient.email

    click_button "Send friend request"

    assert_text I18n.t("friendships.create.success")
    assert_no_link @recipient.username

    switch_user(@recipient)

    visit requests_friendships_path

    click_button "Accept #{@requester.username}"

    assert_text "Friend request accepted."
    assert_current_path requests_friendships_path
    assert_no_button "Accept #{@requester.username}"

    within "main" do
      click_link "Friends", exact: true
    end

    click_link @requester.username

    assert_current_path friend_lists_path(@requester)
    assert_text "Christmas List"

    visit friends_path

    accept_confirm do
      click_button "Remove #{@requester.username}"
    end

    assert_text "You have no friends yet."
    assert_empty @recipient.friends
    assert_empty @requester.friends
  end

  test "crossed requests require acceptance and may be declined" do
    Friendship.create!(requester: @recipient, recipient: @requester)

    visit friends_path

    fill_in "Friend's email address", with: @recipient.email

    click_button "Send friend request"

    assert_current_path requests_friendships_path
    assert_text "You already have an incoming friend request from #{@recipient.username}"
    assert_button "Accept #{@recipient.username}"
    assert_empty @requester.friends

    click_button "Decline #{@recipient.username}"

    assert_text "You have no incoming friend requests."
    assert_empty Friendship.all
  end

  test "unknown email receives generic feedback and no outgoing account details" do
    visit friends_path

    fill_in "Friend's email address", with: "unknown@example.com"

    click_button "Send friend request"

    assert_text I18n.t("friendships.create.success")
    assert_text "You have no friends yet."
    assert_empty Friendship.all
  end

  test "invalid request preserves the email and can be corrected without navigating" do
    visit friends_path

    # A self-request is valid HTML email input but fails server validation.
    fill_in "Friend's email address", with: @requester.email

    click_button "Send friend request"

    assert_text I18n.t("friendships.create.self_request")
    assert_current_path friends_path
    assert_field "Friend's email address", with: @requester.email
    assert_selector "#friends"

    fill_in "Friend's email address", with: @recipient.email

    click_button "Send friend request"

    assert_text I18n.t("friendships.create.success")
    assert_current_path friends_path
    assert_field "Friend's email address", with: ""
    assert_equal 1, Friendship.count
  end

  test "accepting and declining requests preserve an unsent email draft" do
    friendship = Friendship.create!(requester: @recipient, recipient: @requester)

    visit requests_friendships_path

    fill_in "Friend's email address", with: "draft@example.com"

    click_button "Accept #{@recipient.username}"

    assert_text "Friend request accepted."
    assert_current_path requests_friendships_path
    assert_text "You have no incoming friend requests."
    assert_field "Friend's email address", with: "draft@example.com"
    assert friendship.reload.accepted_at.present?

    Friendship.create!(requester: users(:amelia), recipient: @requester)

    visit requests_friendships_path

    fill_in "Friend's email address", with: "another@example.com"

    click_button "Decline amelia"

    assert_text "You have no incoming friend requests."
    assert_field "Friend's email address", with: "another@example.com"
  end

  test "removing a friend refreshes the list but preserves an unsent email draft" do
    Friendship.create!(requester: @requester, recipient: @recipient, accepted_at: Time.current)

    visit friends_path

    fill_in "Friend's email address", with: "draft@example.com"

    accept_confirm do
      click_button "Remove #{@recipient.username}"
    end

    assert_text "You have no friends yet."
    assert_current_path friends_path
    assert_field "Friend's email address", with: "draft@example.com"
    assert_empty @requester.friends
  end

  private

  def switch_user(user)
    sign_out @requester
    sign_out @recipient
    confirm_and_sign_in user
  end
end
