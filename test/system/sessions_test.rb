require "application_system_test_case"

class SessionsTest < ApplicationSystemTestCase
  test "user can log in" do
    user = users(:sean)
    user.confirm

    visit new_user_session_path

    fill_in "Username", with: user.username
    fill_in "Password", with: "test123456"

    click_button "Sign in"

    assert_current_path root_path
  end
end
