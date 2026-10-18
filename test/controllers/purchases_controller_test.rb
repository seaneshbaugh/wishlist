require "test_helper"

class PurchasesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:sean)
    @purchaser = users(:casie)
    @stranger = users(:amelia)
    @list = lists(:christmas_list)
    @item = list_items(:paint_brush)
    @reveal_at = 1.month.from_now.change(sec: 0)
    confirm_and_sign_in @purchaser
  end

  test "creation assigns the authenticated user and ignores ownership parameters" do
    assert_difference "Purchase.count", 1 do
      create_request(user_id: @stranger.id, list_id: lists(:birthday_list).id)
    end

    assert_response :created

    purchase = @item.purchases.sole

    assert_equal @purchaser.id, purchase.user_id
    assert_equal @item.id, purchase.list_item_id
    assert_equal Mime[:turbo_stream], response.media_type
  end

  test "anonymous requests cannot mutate purchases" do
    purchase = existing_purchase

    sign_out @purchaser

    assert_no_difference "Purchase.count" do
      create_request

      assert_response :not_found

      patch purchase_path(purchase), params: { purchase: { notes: "Unauthorized" } }

      assert_response :not_found

      delete purchase_path(purchase)

      assert_response :not_found
    end

    assert_nil purchase.reload.notes
  end

  test "owner cannot purchase own items" do
    confirm_and_sign_in @owner

    assert_no_difference "Purchase.count" do
      create_request

      assert_response :not_found
    end
  end

  test "private lists reject all purchaser operations" do
    purchase = existing_purchase

    @list.update!(public: false)

    assert_no_difference "Purchase.count" do
      create_request

      assert_response :not_found

      confirm_and_sign_in @purchaser

      patch purchase_path(purchase), params: { purchase: { notes: "Unauthorized" } }

      assert_response :not_found

      confirm_and_sign_in @purchaser

      delete purchase_path(purchase)

      assert_response :not_found
    end

    assert_nil purchase.reload.notes
  end

  test "creation rejects hidden items" do
    @item.update!(visible: false)

    assert_no_difference "Purchase.count" do
      create_request

      assert_response :not_found
    end
  end

  test "creation scopes the item to the route list" do
    foreign_item = lists(:birthday_list).list_items.create!(name: "Other item")

    assert_no_difference "Purchase.count" do
      create_request(list_item_id: foreign_item.id)

      assert_response :not_found
    end
  end

  test "purchase lookup scopes both list and owner" do
    purchase = existing_purchase

    assert_no_difference "Purchase.count" do
      patch user_list_purchase_path(@owner, lists(:birthday_list), purchase), params: { purchase: { notes: "Wrong list" } }

      assert_response :not_found

      confirm_and_sign_in @purchaser

      delete user_list_purchase_path(@stranger, @list, purchase)

      assert_response :not_found
    end

    assert_nil purchase.reload.notes
  end

  test "update ignores submitted purchaser and item identifiers" do
    purchase = existing_purchase

    patch purchase_path(purchase), params: {
            purchase: {
              notes: "Updated",
              user_id: @stranger.id,
              list_item_id: list_items(:football).id
            }
          }, as: :turbo_stream

    assert_response :success
    assert_equal "Updated", purchase.reload.notes
    assert_equal @purchaser.id, purchase.user_id
    assert_equal @item.id, purchase.list_item_id
  end

  %w[owner stranger].each do |role|
    test "#{role} cannot update or delete an unrevealed purchase" do
      purchase = existing_purchase

      confirm_and_sign_in instance_variable_get("@#{role}")

      patch purchase_path(purchase), params: { purchase: { notes: "Unauthorized" } }

      assert_response :not_found

      confirm_and_sign_in instance_variable_get("@#{role}")

      assert_no_difference "Purchase.count" do
        delete purchase_path(purchase)

        assert_response :not_found
      end

      assert_nil purchase.reload.notes
    end
  end

  test "purchaser can update and delete an unrevealed purchase" do
    purchase = existing_purchase

    patch purchase_path(purchase), params: { purchase: { quantity: 2 } }, as: :turbo_stream

    assert_response :success
    assert_equal 2, purchase.reload.quantity

    assert_difference "Purchase.count", -1 do
      delete purchase_path(purchase), as: :turbo_stream

      assert_response :success
    end
  end

  %w[purchaser stranger].each do |role|
    test "#{role} cannot update or delete a revealed purchase" do
      purchase = existing_purchase(reveal_at: 1.day.ago)

      confirm_and_sign_in instance_variable_get("@#{role}")

      patch purchase_path(purchase), params: { purchase: { notes: "Unauthorized" } }

      assert_response :not_found

      confirm_and_sign_in instance_variable_get("@#{role}")

      assert_no_difference "Purchase.count" do
        delete purchase_path(purchase)

        assert_response :not_found
      end

      assert_nil purchase.reload.notes
    end
  end

  test "owner cannot edit a revealed purchase but can delete it on a private list" do
    purchase = existing_purchase(reveal_at: 1.day.ago)

    @list.update!(public: false)

    confirm_and_sign_in @owner

    patch purchase_path(purchase), params: { purchase: { notes: "Unauthorized" } }

    assert_response :not_found

    confirm_and_sign_in @owner

    assert_difference "Purchase.count", -1 do
      delete purchase_path(purchase), as: :turbo_stream

      assert_response :success
    end
  end

  test "purchase is revealed at the exact reveal timestamp" do
    purchase = existing_purchase

    travel_to @reveal_at do
      confirm_and_sign_in @purchaser

      patch purchase_path(purchase), params: { purchase: { notes: "Too late" } }

      assert_response :not_found

      confirm_and_sign_in @owner

      delete purchase_path(purchase), as: :turbo_stream

      assert_response :success

      assert_not Purchase.exists?(purchase.id)
    end
  end

  test "second unrevealed purchase is rejected without changing the existing one" do
    original = existing_purchase

    assert_no_difference "Purchase.count" do
      create_request

      assert_response :unprocessable_entity
    end

    assert_equal 1, original.reload.quantity
  end

  test "historical purchases permit another purchase while quantity remains" do
    historical = existing_purchase(reveal_at: 1.day.ago)

    assert_difference "Purchase.count", 1 do
      create_request

      assert_response :created
    end

    assert historical.reload.revealed?
    assert_equal 2, @item.purchases.count
  end

  test "quantity limits include revealed purchases and other purchasers" do
    existing_purchase(user: @stranger, quantity: 2, reveal_at: 1.day.ago)

    assert_no_difference "Purchase.count" do
      create_request(quantity: 2)

      assert_response :unprocessable_entity
    end

    assert_difference "Purchase.count", 1 do
      create_request(quantity: 1)

      assert_response :created
    end
  end

  test "invalid updates leave all submitted attributes unchanged" do
    purchase = existing_purchase(notes: "Original")

    existing_purchase(user: @stranger, quantity: 2)

    patch purchase_path(purchase), params: { purchase: { quantity: 2, notes: "Changed" } }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_equal 1, purchase.reload.quantity
    assert_equal "Original", purchase.notes
    assert_select "turbo-stream[action='replace'][target='purchase_form_list_item_#{@item.id}']", count: 1
    assert_select "turbo-stream[target='list-items']", count: 0
  end

  [ nil, "not a date" ].each do |date|
    test "invalid reveal date #{date.inspect} returns a validation response" do
      assert_no_difference "Purchase.count" do
        create_request(reveal_at: date)

        assert_response :unprocessable_entity
      end

      assert_select "turbo-stream[action='replace'][target='purchase_form_list_item_#{@item.id}']", count: 1
    end
  end

  [ 0, -1, 1.5, "invalid" ].each do |quantity|
    test "invalid quantity #{quantity.inspect} is rejected" do
      assert_no_difference "Purchase.count" do
        create_request(quantity: quantity)

        assert_response :unprocessable_entity
      end
    end
  end

  %i[patch delete].each do |verb|
    test "#{verb} rechecks permission when the purchase reveals during lock acquisition" do
      purchase = existing_purchase(reveal_at: 1.minute.from_now.change(sec: 0), notes: "Original")

      after_item_lock(-> { travel_to purchase.reveal_at }) do
        public_send verb, purchase_path(purchase), params: { purchase: { notes: "Changed" } }, as: :turbo_stream
      end

      assert_response :not_found
      assert_equal "Original", purchase.reload.notes
    end

    test "#{verb} reloads a reveal date changed during lock acquisition" do
      purchase = existing_purchase(notes: "Original")
      change = -> { Purchase.where(id: purchase.id).update_all(reveal_at: 1.day.ago) }

      after_item_lock(change) do
        public_send verb, purchase_path(purchase), params: { purchase: { notes: "Changed" } }, as: :turbo_stream
      end

      assert_response :not_found
      assert_equal "Original", purchase.reload.notes
    end

    test "#{verb} returns not found when the purchase disappeared during lock acquisition" do
      purchase = existing_purchase
      change = -> { Purchase.where(id: purchase.id).delete_all }

      after_item_lock(change) do
        public_send verb, purchase_path(purchase), params: { purchase: { notes: "Changed" } }, as: :turbo_stream
      end

      assert_response :not_found
    end
  end

  test "owner cannot delete a purchase whose reveal was postponed during lock acquisition" do
    purchase = existing_purchase(reveal_at: 1.day.ago)

    confirm_and_sign_in @owner

    change = -> { Purchase.where(id: purchase.id).update_all(reveal_at: 1.day.from_now) }

    after_item_lock(change) do
      delete purchase_path(purchase), as: :turbo_stream
    end

    assert_response :not_found
    assert Purchase.exists?(purchase.id)
  end

  private

  def purchase_path(purchase)
    user_list_purchase_path(@owner, @list, purchase)
  end

  def create_request(**attributes)
    post user_list_purchases_path(@owner, @list), params: {
      purchase: { list_item_id: @item.id, quantity: 1, reveal_at: @reveal_at }.merge(attributes)
    }, as: :turbo_stream
  end

  def existing_purchase(**attributes)
    @item.purchases.create!({ user: @purchaser, quantity: 1, reveal_at: @reveal_at }.merge(attributes))
  end

  # Inject the state a waiting request would encounter once its item lock is
  # acquired, before it reloads the purchase. These are deterministic regression
  # tests, not simultaneous-connection tests of PostgreSQL's locking behavior.
  # Database changes injected here share the request transaction and roll back
  # with it when authorization raises RecordNotFound.
  def after_item_lock(change)
    triggered = false
    subscriber = lambda do |*, payload|
      if !triggered && payload[:sql].include?('"list_items"') && payload[:sql].include?("FOR UPDATE")
        triggered = true

        change.call
      end
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      yield
    end

    assert triggered, "Expected the request to acquire the list item lock"
  end
end
