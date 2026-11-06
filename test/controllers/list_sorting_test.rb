require "test_helper"

class ListSortingTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:sean)
    @viewer = users(:casie)
    @list = lists(:christmas_list)
    @football = list_items(:football)
    @cat = list_items(:lucky_cat)
    @brush = list_items(:paint_brush)
    Friendship.create!(requester: @owner, recipient: @viewer, accepted_at: Time.current)
    confirm_and_sign_in @viewer
  end

  test "price sorts cross priority groups and display priority labels without changing stored order" do
    before = @list.list_items.order(:id).pluck(:id, :priority, :position)

    get friend_list_path(@owner, @list), params: { sort: "price_asc" }

    assert_response :success
    assert_equal [ @cat.id, @brush.id, @football.id ], rendered_item_ids
    assert_select "#list-items section", count: 0
    assert_select "#list-items [data-id='#{@football.id}'] span", text: "Highest priority"

    get friend_list_path(@owner, @list), params: { sort: "price_desc" }

    assert_response :success
    assert_equal [ @football.id, @brush.id, @cat.id ], rendered_item_ids
    assert_equal before, @list.list_items.order(:id).pluck(:id, :priority, :position)
  end

  test "unpriced items sort last in both directions and zero is a real price" do
    @football.update!(price: nil)
    @cat.update!(price: 0)

    get friend_list_path(@owner, @list), params: { sort: "price_asc" }

    assert_equal [ @cat.id, @brush.id, @football.id ], rendered_item_ids

    get friend_list_path(@owner, @list), params: { sort: "price_desc" }

    assert_equal [ @brush.id, @cat.id, @football.id ], rendered_item_ids
  end

  test "price ties use priority then manual position then ID in both directions" do
    @football.update!(priority: :high, position: 2)
    @cat.update!(position: 1)
    @brush.update!(priority: :highest)

    extra = @list.list_items.create!(name: "Equal price", priority: :high)

    extra.update!(position: 1)

    expected = [ @brush.id, *[ @cat.id, extra.id ].sort, @football.id ]

    [ 10, nil ].each do |price|
      @list.list_items.update_all(price: price)

      %w[price_asc price_desc].each do |sort|
        get friend_list_path(@owner, @list), params: { sort: sort }

        assert_response :success
        assert_equal expected, rendered_item_ids
      end
    end
  end

  test "default and invalid sorts retain priority groups and manual order" do
    [ nil, "priority", "unknown", "price DESC; DROP TABLE list_items", [ "price_asc" ], { direction: "asc" } ].each do |sort|
      get friend_list_path(@owner, @list), params: { sort: sort }

      assert_response :success
      assert_equal [ @football.id, @cat.id, @brush.id ], rendered_item_ids
      assert_select "#list-items section", count: 3
      assert_select "#list-items span", text: / priority\z/, count: 0
    end
  end

  test "owner ignores price sorting and retains hidden items and drag handles" do
    @football.update!(visible: false)

    sign_out @viewer

    confirm_and_sign_in @owner

    %w[price_asc price_desc].each do |sort|
      get list_path(@list), params: { sort: sort }

      assert_response :success
      assert_equal [ @football.id, @cat.id, @brush.id ], rendered_item_ids
      assert_select "#list-items section", count: 3
      assert_select "#list-items [data-reorder-handle]", count: 3
      assert_select "select[name='sort']", count: 0
    end
  end

  test "sorted views retain visibility rules and the visible item summary" do
    @football.update!(visible: false)
    @cat.purchases.create!(user: users(:amelia), quantity: 1, reveal_at: 1.day.from_now)
    @brush.purchases.create!(user: @viewer, quantity: 3, reveal_at: 1.day.ago)

    %w[price_asc price_desc].each do |sort|
      get friend_list_path(@owner, @list), params: { sort: sort }

      assert_response :success
      assert_equal [ @brush.id ], rendered_item_ids
      assert_select "#list-item-summary", text: /1 item/
    end
  end

  test "sorted empty lists render successfully" do
    get friend_list_path(@owner, lists(:birthday_list)), params: { sort: "price_asc" }

    assert_response :success
    assert_empty rendered_item_ids
    assert_select "#list-items section", count: 0
    assert_select "#list-item-summary", text: /0 items/
  end

  test "sort controls and list render together with the selection from the URL" do
    get friend_list_path(@owner, @list), params: { sort: "price_desc" }

    assert_response :success

    assert_select "#list-browser" do
      assert_select "form[method='get'][data-turbo-action='advance']"
      assert_select "select[name='sort'] option[selected][value='price_desc']"
      assert_select "#list-items"
    end

    assert_select "form input[name='sort'][value='price_desc']", count: 3
  end

  test "sort parameters grant no access to private lists or former friends" do
    @list.update!(public: false)

    get friend_list_path(@owner, @list), params: { sort: "price_asc" }

    assert_response :not_found

    @list.update!(public: true)
    Friendship.between(@owner, @viewer).destroy!

    get friend_list_path(@owner, @list), params: { sort: "price_desc" }

    assert_response :not_found
  end

  test "sorted rendering does not add queries per item" do
    path = friend_list_path(@owner, @list, sort: "price_asc")

    get path

    before = select_count(path)

    4.times do |number|
      item = @list.list_items.create!(name: "Additional item #{number}", quantity: 2, price: number)

      item.purchases.create!(user: @viewer, quantity: 1, reveal_at: 1.day.from_now)
    end

    assert_equal before, select_count(path)
  end

  private

  def rendered_item_ids
    css_select("#list-items [data-controller='list-item']").map { |item| item["data-id"].to_i }
  end

  def select_count(path)
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
