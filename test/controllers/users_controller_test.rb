require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  test "index" do
    confirm_and_sign_in(users(:sean))

    get users_path

    assert_response :success
  end
end
