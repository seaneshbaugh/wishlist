require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:sean)
    confirm_and_sign_in @user
  end

  test "account links lead directly to the edit page and there is no show route" do
    get lists_path

    assert_select "a[href='#{edit_account_path}']", text: "Your Account", count: 2

    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path(account_path, method: :get)
    end
  end

  test "deletion confirmation explains the consequences and asks for the current username" do
    get confirm_delete_account_path

    assert_response :success
    assert_select "h1", text: "Delete Account"
    assert_select "#deletion-confirmation-help strong", text: @user.username
    assert_select "form[action='#{account_path}'] input[name='_method'][value='delete']"
    assert_select "input[name='confirmation'][required]"
    assert_select "a[href='#{edit_account_path}']", text: "Keep My Account"
  end

  test "edit renders the account fields and a separate deletion confirmation link" do
    get edit_account_path

    assert_response :success
    assert_select "h1", text: "Edit Account"
    assert_select "form[action='#{account_path}'] input[name='_method'][value='patch']"
    assert_select "input[name='account[username]'][value='#{@user.username}']"
    assert_select "input[name='account[email]'][value='#{@user.email}']"

    %w[password password_confirmation current_password].each do |attribute|
      assert_select "input[type='password'][name='account[#{attribute}]']"
    end

    assert_select "a[href='#{confirm_delete_account_path}']", text: "Delete My Account"
  end

  test "username-only updates need no password and ignore ownership and confirmation attributes" do
    original_password = @user.encrypted_password

    patch account_path, params: { account: {
      username: "new_username", email: @user.email, password: "", password_confirmation: "",
      id: users(:casie).id, confirmed_at: nil, unconfirmed_email: "other@example.com"
    } }

    assert_redirected_to edit_account_path
    assert_equal "new_username", @user.reload.username
    assert_equal original_password, @user.encrypted_password
    assert @user.confirmed?
    assert_nil @user.unconfirmed_email
    assert_equal "casie", users(:casie).username

    follow_redirect!

    assert_response :success
    assert_select "input[name='account[username]'][value='new_username']"
  end

  [ nil, "wrong-password" ].each do |current_password|
    test "email and password changes require a valid current password (#{current_password.inspect})" do
      original = @user.attributes.slice("username", "email", "unconfirmed_email", "encrypted_password")

      [ { email: "changed@example.com" }, { password: "new-password-123", password_confirmation: "new-password-123" } ].each do |changes|
        assert_no_enqueued_jobs do
          patch account_path, params: { account: changes.merge(username: "changed_name", current_password: current_password) }
        end

        assert_response :unprocessable_entity
        assert_select "#account_current_password[aria-invalid='true']"
        assert_select "[role='alert']", text: /Current password/
        assert_equal original, @user.reload.attributes.slice(*original.keys)
        assert_password_fields_empty
      end
    end
  end

  test "valid password changes keep the current session signed in" do
    patch account_path, params: { account: {
      password: "new-password-123", password_confirmation: "new-password-123", current_password: "test123456"
    } }

    assert_redirected_to edit_account_path
    assert @user.reload.valid_password?("new-password-123")
    assert_not @user.valid_password?("test123456")

    follow_redirect!

    assert_response :success
    assert_password_fields_empty
  end

  test "blank password confirmation is rejected and submitted passwords are never echoed" do
    patch account_path, params: { account: {
      password: "new-password-123", password_confirmation: "", current_password: "test123456"
    } }

    assert_response :unprocessable_entity
    assert_select "#account_password_confirmation[aria-invalid='true']"
    assert @user.reload.valid_password?("test123456")
    assert_password_fields_empty
  end

  test "email changes require confirmation and enqueue the email through a job" do
    original_email = @user.email

    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
      patch account_path, params: { account: { email: "new-address@example.com", current_password: "test123456" } }
    end

    assert_redirected_to edit_account_path
    assert_equal original_email, @user.reload.email
    assert_equal "new-address@example.com", @user.unconfirmed_email

    follow_redirect!

    assert_response :success
    assert_select "input[name='account[email]'][value='#{original_email}']"
    assert_select "strong", text: "new-address@example.com"
    assert_password_fields_empty
  end

  test "username validation errors retain the draft on the edit page" do
    patch account_path, params: { account: { username: "invalid name" } }

    assert_response :unprocessable_entity
    assert_select "h1", text: "Edit Account"
    assert_select "input[name='account[username]'][value='invalid name'][aria-invalid='true']"
    assert_equal "sean", @user.reload.username
  end

  test "deletion rejects missing mismatched and differently cased usernames" do
    [ nil, "another_user", @user.username.upcase ].each do |confirmation|
      assert_no_difference "User.count" do
        delete account_path, params: { confirmation: confirmation }
      end

      assert_response :unprocessable_entity
      assert_select "h1", text: "Delete Account"
      assert_select "[role='alert']", text: I18n.t("accounts.destroy.error_confirmation")
    end
  end

  test "deleting the current account removes its data and signs the user out" do
    other_user = users(:casie)
    Friendship.create!(requester: @user, recipient: other_user, accepted_at: Time.current)
    invitation = @user.sent_invitations.create!(email: "invited@example.com")
    list_ids = @user.lists.ids

    assert_difference "User.count", -1 do
      delete account_path, params: { confirmation: @user.username, user_id: other_user.id }
    end

    assert_redirected_to root_path
    assert_not List.where(id: list_ids).exists?
    assert_not Invitation.exists?(invitation.id)
    assert_not Friendship.where(requester_id: @user.id).or(Friendship.where(recipient_id: @user.id)).exists?
    assert User.exists?(other_user.id)

    follow_redirect!

    assert_response :success
    assert_select "form[action='#{user_session_path}']"
  end

  test "failed account deletion stays on the confirmation page without a sticky flash" do
    user_id = @user.id
    prevent_destroy = ->(user) { throw :abort if user.id == user_id }

    User.set_callback(:destroy, :before, prevent_destroy)

    begin
      assert_no_difference "User.count" do
        delete account_path, params: { confirmation: @user.username }
      end

      assert_response :unprocessable_entity
      assert_select "h1", text: "Delete Account"
      assert_includes response.body, I18n.t("accounts.destroy.error")

      get edit_account_path

      assert_response :success
      assert_not_includes response.body, I18n.t("accounts.destroy.error")
    ensure
      User.skip_callback(:destroy, :before, prevent_destroy)
    end
  end

  test "anonymous visitors cannot access account pages or delete accounts" do
    sign_out @user

    get edit_account_path

    assert_response :not_found

    get confirm_delete_account_path

    assert_response :not_found

    assert_no_difference "User.count" do
      delete account_path, params: { confirmation: @user.username }
    end

    assert_response :not_found

    patch account_path, params: { account: { username: "unauthorized" } }

    assert_response :not_found
    assert_equal "sean", @user.reload.username
  end

  private

  def assert_password_fields_empty
    assert_select "input[type='password']" do |fields|
      assert_equal 3, fields.size
      fields.each { |field| assert_empty field["value"].to_s }
    end
  end
end
