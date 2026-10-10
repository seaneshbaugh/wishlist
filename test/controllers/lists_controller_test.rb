class ListsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:sean)
    confirm_and_sign_in @user
  end

  test "index" do
    get lists_path

    assert_response :success
  end

  test "user reorders lists" do
    confirm_and_sign_in(users(:sean))

    first = lists(:christmas_list)
    second = lists(:birthday_list)

    first.update!(position: 0)
    second.update!(position: 1)

    patch reorder_lists_path(format: :json), params: {
            positions: [
              { id: first.id, position: 1 },
              { id: second.id, position: 0 }
            ]
          }

    assert_response :no_content

    assert_equal 1, first.reload.position
    assert_equal 0, second.reload.position
  end

  test "reorder rejects missing lists" do
    first = lists(:christmas_list)

    patch reorder_lists_path(format: :json), params: {
            positions: [
              { id: first.id, position: 0 }
            ]
          }

    assert_response :unprocessable_entity
  end

  test "reorder rejects duplicate ids" do
    first = lists(:christmas_list)

    patch reorder_lists_path(format: :json), params: {
            positions: [
              { id: first.id, position: 0 },
              { id: first.id, position: 1 }
            ]
          }

    assert_response :unprocessable_entity
  end

  test "reorder rejects invalid positions" do
    first = lists(:christmas_list)
    second = lists(:birthday_list)

    patch reorder_lists_path(format: :json), params: {
            positions: [
              { id: first.id, position: 0 },
              { id: second.id, position: 2 }
            ]
          }

    assert_response :unprocessable_entity
  end
end
