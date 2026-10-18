require "test_helper"

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

  test "index counts all owner items including hidden and fulfilled items and empty lists" do
    @item.update!(visible: false)

    list_items(:lucky_cat).purchases.create!(user: @viewer, quantity: 1, reveal_at: 1.day.from_now)

    @list.update!(public: false)

    get lists_path

    assert_response :success
    assert_select "[data-reorder-target='item'][data-id='#{@list.id}'] span", text: "3 items", count: 1
    assert_select "[data-reorder-target='item'][data-id='#{lists(:birthday_list).id}'] span", text: "0 items", count: 1
  end

  test "index counts only viewer-visible items while retaining historical purchases" do
    @item.update!(visible: false)

    list_items(:lucky_cat).purchases.create!(user: users(:amelia), quantity: 1, reveal_at: 1.day.from_now)
    list_items(:paint_brush).purchases.create!(user: @viewer, quantity: 3, reveal_at: 1.day.ago)

    private_list = @owner.lists.create!(name: "Private wishlist", description: "", public: false)

    private_list.list_items.create!(name: "Private item")

    switch_user @viewer

    get user_lists_path(@owner)

    assert_response :success
    assert_select "[data-reorder-target='item'][data-id='#{@list.id}'] span", text: "1 item", count: 1
    assert_select "[data-reorder-target='item'][data-id='#{lists(:birthday_list).id}'] span", text: "0 items", count: 1
    assert_select "[data-reorder-target='item'][data-id='#{private_list.id}']", count: 0
  end

  test "index query count does not grow with the number of lists for owners or viewers" do
    # Warm up rendering before measuring database queries.
    get lists_path

    owner_before = index_select_count(lists_path)

    switch_user @viewer

    get user_lists_path(@owner)

    viewer_before = index_select_count(user_lists_path(@owner))

    4.times do |number|
      list = @owner.lists.create!(name: "Extra wishlist #{number}", description: "")
      list.list_items.create!(name: "Extra item")
    end

    assert_equal viewer_before, index_select_count(user_lists_path(@owner))

    switch_user @owner

    get lists_path

    assert_equal owner_before, index_select_count(lists_path)
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

  def index_select_count(path)
    queries = []
    subscriber = lambda do |*, payload|
      queries << payload[:sql] if payload[:sql].match?(/\ASELECT/i) && payload[:name] != "SCHEMA"
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      get path
    end

    assert_response :success

    queries.size
  end
end
