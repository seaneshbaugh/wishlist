require "test_helper"

class SessionTimeoutTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:sean)
    @user.confirm

    post user_session_path, params: { user: { username: @user.username, password: "test123456", remember_me: "0" } }
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  test "an expired session shows the timeout message without Devise's internal flag" do
    travel User.timeout_in + 1.second do
      get root_path

      assert_response :redirect

      3.times do
        break unless response.redirect?

        follow_redirect!
      end

      assert_response :success
      assert_select "form[action='#{user_session_path}']"
      assert_equal true, flash[:timedout]
      assert_select "main div", text: I18n.t("devise.failure.timeout"), count: 1
      assert_select "main div", text: "true", count: 0
    end
  end

  test "ordinary sign-out notices still appear" do
    delete destroy_user_session_path

    follow_redirect!

    assert_response :success
    assert_select "main div", text: I18n.t("devise.sessions.signed_out"), count: 1
  end
end
