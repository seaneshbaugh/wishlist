require "test_helper"

class HelpControllerTest < ActionDispatch::IntegrationTest
  test "help is available before sign-in and covers all four workflows" do
    get help_path

    assert_response :success
    assert_select "title", text: "Using Wishlist · Help"
    assert_select "h1", text: "Using Wishlist"

    %w[invitations friend-requests managing-lists purchases].each do |section|
      assert_select "article section##{section} h2"
      assert_select "nav[aria-label='Help sections'] a[href='##{section}']"
    end

    assert_select "figure img[alt][loading='lazy']", count: 5
    assert_select "header a[href='#{help_path}']", text: "Help", count: 2
  end

  test "signed-in users can open help from both navigation menus" do
    confirm_and_sign_in users(:sean)

    get help_path

    assert_response :success
    assert_select "header a[href='#{help_path}']", text: "Help", count: 2
  end
end
