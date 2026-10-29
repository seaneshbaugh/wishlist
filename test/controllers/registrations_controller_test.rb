require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "registration requires an invitation on both GET and POST" do
    get new_user_registration_path

    assert_response :not_found

    assert_no_difference "User.count" do
      post user_registration_path, params: { user: { username: "newuser", email: "new@example.com",
        password: "test123456", password_confirmation: "test123456" } }
    end

    assert_response :not_found
  end

  test "registration aliases use the same invitation flow" do
    invitation = users(:sean).sent_invitations.create!(email: "new@example.com")

    get new_user_registration_path(token: invitation.acceptance_token)

    assert_response :success

    post user_registration_path, params: { token: invitation.acceptance_token,
      user: { username: "newuser", password: "test123456", password_confirmation: "test123456" } }

    assert_redirected_to friends_path
    assert User.find_by!(email: invitation.email).confirmed?
  end

  test "login page has no unrestricted signup link" do
    get new_user_session_path

    assert_select "a[href='#{new_user_registration_path}']", count: 0
  end
end
