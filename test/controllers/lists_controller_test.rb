class ListsControllerTest < ActionDispatch::IntegrationTest
  test "index" do
    confirm_and_sign_in(users(:sean))

    get lists_path

    assert_response :success
  end
end
