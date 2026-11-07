require "application_system_test_case"

class AccountsTest < ApplicationSystemTestCase
  setup do
    @user = users(:sean)
    confirm_and_sign_in @user
  end

  teardown do
    page.current_window.resize_to(1400, 1400)
  end

  test "user edits a username with inline validation and keeps the existing password" do
    visit edit_account_path

    fill_in "Username", with: "invalid name"

    click_button "Save Changes"

    assert_selector "#account_username[aria-invalid='true']"
    assert_field "Username", with: "invalid name"
    assert_equal "sean", @user.reload.username

    fill_in "Username", with: "sean_updated"

    click_button "Save Changes"

    assert_text "Your account has been updated."
    assert_current_path edit_account_path
    assert_field "Username", with: "sean_updated"
    assert @user.reload.valid_password?("test123456")

    page.save_screenshot(Rails.root.join("tmp/screenshots/account-edit-desktop.png"))
  end

  test "email change requires the current password and shows pending confirmation" do
    visit edit_account_path

    fill_in "Email", with: "new-address@example.com"

    click_button "Save Changes"

    assert_selector "#account_current_password[aria-invalid='true']"
    assert_field "Email", with: "new-address@example.com"
    assert_equal "sean@seaneshbaugh.com", @user.reload.email

    fill_in "Current password", with: "test123456"

    click_button "Save Changes"

    assert_text "Awaiting confirmation of new-address@example.com."
    assert_field "Email", with: "sean@seaneshbaugh.com"
    assert_field "Current password", with: ""
    assert_equal "new-address@example.com", @user.reload.unconfirmed_email
  end

  test "password validation clears secrets and a valid change keeps the session signed in" do
    visit edit_account_path

    fill_in "New password", with: "new-password-123", exact: true
    fill_in "Confirm new password", with: "different-password"
    fill_in "Current password", with: "test123456"

    click_button "Save Changes"

    assert_selector "#account_password_confirmation[aria-invalid='true']"
    assert_field "New password", with: "", exact: true
    assert_field "Confirm new password", with: ""
    assert_field "Current password", with: ""

    fill_in "New password", with: "new-password-123", exact: true
    fill_in "Confirm new password", with: "new-password-123"
    fill_in "Current password", with: "test123456"

    click_button "Save Changes"

    assert_text "Your account has been updated."
    assert_current_path edit_account_path
    assert @user.reload.valid_password?("new-password-123")
    assert_field "Current password", with: ""
  end

  test "narrow account pages support cancelling deletion and require a matching username to delete" do
    page.current_window.resize_to(500, 900)

    visit edit_account_path

    page.save_screenshot(Rails.root.join("tmp/screenshots/account-edit-mobile.png"))

    click_link "Delete My Account"

    assert_current_path confirm_delete_account_path
    assert_text "This cannot be undone."

    page.save_screenshot(Rails.root.join("tmp/screenshots/account-delete-mobile.png"))

    click_link "Keep My Account"

    assert_current_path edit_account_path
    assert User.exists?(@user.id)

    click_link "Delete My Account"

    fill_in "Confirm your username", with: "wrong_username"

    click_button "Delete My Account"

    assert_selector "h1", text: "Delete Account"
    assert_text "The username does not match."
    assert_field "Confirm your username", with: "wrong_username"
    assert User.exists?(@user.id)

    fill_in "Confirm your username", with: @user.username

    click_button "Delete My Account"

    assert_selector "form[action='#{user_session_path}']"
    assert_text "Your account has been deleted."
    assert_not User.exists?(@user.id)
  end
end
