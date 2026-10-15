class ListsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:sean)
    @viewer = users(:casie)
    @list = lists(:christmas_list)
    @item = list_items(:football)
    confirm_and_sign_in @owner
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

  test "public lists are accessible but private lists are omitted and inaccessible" do
    switch_user @viewer

    private_list = lists(:birthday_list)
    private_list.update!(public: false)

    get user_lists_path(@owner)

    assert_response :success
    assert_select "h2", text: @list.name
    assert_select "h2", text: private_list.name, count: 0

    get user_list_path(@owner, @list)

    assert_response :success

    get user_list_path(@owner, private_list)

    assert_response :not_found
  end

  test "owner can view private lists and hidden or fulfilled items" do
    @list.update!(public: false)
    @item.update!(visible: false)

    get list_path(@list)

    assert_response :success
    assert_select item_selector, count: 1

    get user_list_path(@owner, @list)

    assert_response :success
  end

  test "hidden items and items fulfilled by someone else are omitted" do
    switch_user @viewer

    @item.update!(visible: false)

    get user_list_path(@owner, @list)

    assert_response :success
    assert_select item_selector, count: 0

    @item.update!(visible: true)
    @item.purchases.create!(user: users(:amelia), quantity: 1, reveal_at: 1.day.ago)

    get user_list_path(@owner, @list)

    assert_response :success
    assert_select item_selector, count: 0
  end

  test "historical purchaser retains visibility unless item is hidden or list becomes private" do
    switch_user @viewer

    @item.purchases.create!(user: @viewer, quantity: 1, reveal_at: 1.day.ago)

    get user_list_path(@owner, @list)

    assert_response :success
    assert_select item_selector, count: 1

    @item.update!(visible: false)

    get user_list_path(@owner, @list)

    assert_response :success
    assert_select item_selector, count: 0

    @list.update!(public: false)

    get user_list_path(@owner, @list)

    assert_response :not_found
  end

  test "viewer cannot access owner edit routes or mutate another users list" do
    switch_user @viewer

    get edit_list_path(@list)
    assert_response :not_found

    confirm_and_sign_in @viewer

    patch list_path(@list), params: { list: { name: "Unauthorized", public: false } }

    assert_response :not_found

    assert_no_difference "List.count" do
      confirm_and_sign_in @viewer
      delete list_path(@list)
      assert_response :not_found
    end

    assert_equal "Christmas List", @list.reload.name
    assert @list.public?

    confirm_and_sign_in @viewer

    patch reorder_lists_path, params: { positions: [ { id: @list.id, position: 0 } ] }, as: :json

    assert_response :unprocessable_entity
    assert_equal 0, @list.reload.position
  end

  test "list lookup rejects a different route owner" do
    switch_user @viewer

    get user_list_path(users(:amelia), @list)

    assert_response :not_found
  end

  test "anonymous visitors cannot access lists or mutate them" do
    sign_out @owner

    get user_list_path(@owner, @list)

    assert_response :not_found

    assert_no_difference "List.count" do
      post lists_path, params: { list: { name: "Unauthorized" } }

      assert_response :not_found

      delete list_path(@list)

      assert_response :not_found
    end

    patch list_path(@list), params: { list: { name: "Unauthorized" } }

    assert_response :not_found

    patch reorder_lists_path, params: { positions: [ { id: @list.id, position: 0 } ] }, as: :json

    assert_response :unauthorized
    assert_equal "Christmas List", @list.reload.name
  end

  private

  def switch_user(user)
    sign_out @owner
    sign_out @viewer
    confirm_and_sign_in user
  end

  def item_selector
    "[data-controller='list-item'][data-id='#{@item.id}']"
  end
end
