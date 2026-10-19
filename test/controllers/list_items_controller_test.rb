require "test_helper"

class ListItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:sean)
    @list = lists(:christmas_list)
    @item = list_items(:football)
    confirm_and_sign_in @owner
  end

  test "non-owner cannot create update delete or reorder items" do
    confirm_and_sign_in users(:casie)

    assert_no_difference "ListItem.count" do
      post list_list_items_path(@list), params: { list_item: { name: "Unauthorized" } }

      assert_response :not_found

      confirm_and_sign_in users(:casie)

      patch list_list_item_path(@list, @item), params: { list_item: { name: "Unauthorized" } }

      assert_response :not_found

      confirm_and_sign_in users(:casie)

      delete list_list_item_path(@list, @item)

      assert_response :not_found

      confirm_and_sign_in users(:casie)

      patch reorder_list_list_items_path(@list), params: { positions: positions }, as: :json

      assert_response :not_found
    end

    assert_equal "Football", @item.reload.name
  end

  test "anonymous requests cannot mutate items" do
    sign_out @owner

    assert_no_difference "ListItem.count" do
      post list_list_items_path(@list), params: { list_item: { name: "Unauthorized" } }

      assert_response :not_found

      patch list_list_item_path(@list, @item), params: { list_item: { name: "Unauthorized" } }

      assert_response :not_found

      delete list_list_item_path(@list, @item)

      assert_response :not_found

      patch reorder_list_list_items_path(@list), params: { positions: positions }, as: :json

      assert_response :unauthorized
    end

    assert_equal "Football", @item.reload.name
  end

  test "item lookup rejects a different parent list" do
    other_list = lists(:birthday_list)

    patch list_list_item_path(other_list, @item), params: { list_item: { name: "Wrong parent" } }

    assert_response :not_found

    assert_no_difference "ListItem.count" do
      delete list_list_item_path(other_list, @item)

      assert_response :not_found
    end

    assert_equal "Football", @item.reload.name
  end

  test "creation ignores submitted parent and owner identifiers" do
    post list_list_items_path(@list), params: { list_item: {
      name: "New item", list_id: lists(:birthday_list).id, user_id: users(:casie).id
    } }, as: :turbo_stream

    assert_response :created
    assert_equal @list.id, ListItem.find_by!(name: "New item").list_id
  end

  test "invalid form identity is rejected without saving" do
    assert_no_difference "ListItem.count" do
      post list_list_items_path(@list), params: { list_item: { name: "" }, form_id: "list-items" }, as: :turbo_stream

      assert_response :bad_request
    end
  end

  test "reorder persists a complete permutation across priorities" do
    submitted = positions.map { |entry| entry.merge(priority: "high") }

    patch reorder_list_list_items_path(@list), params: { positions: submitted }, as: :json

    assert_response :no_content

    submitted.each do |entry|
      item = ListItem.find(entry[:id])

      assert_equal "high", item.priority
      assert_equal entry[:position], item.position
    end
  end

  %w[missing duplicate foreign invalid_priority invalid_position].each do |problem|
    test "reorder rejects #{problem} entries without partial changes" do
      before = @list.list_items.order(:id).pluck(:id, :priority, :position)

      submitted = positions

      case problem
      when "missing" then submitted.pop
      when "duplicate" then submitted.last[:id] = submitted.first[:id]
      when "foreign" then submitted.last[:id] = lists(:birthday_list).list_items.create!(name: "Other item").id
      when "invalid_priority" then submitted.last[:priority] = "urgent"
      when "invalid_position" then submitted.last[:position] = 99
      end

      patch reorder_list_list_items_path(@list), params: { positions: submitted }, as: :json

      assert_response :unprocessable_entity

      assert_equal before, @list.list_items.order(:id).pluck(:id, :priority, :position)
    end
  end

  %i[id position].each do |attribute|
    [ nil, "", "oops", "1oops", "1.0", "1e0", -1, 1.0, true, [], {} ].each do |value|
      test "reorder rejects #{attribute} #{value.inspect} without changes" do
        before = @list.list_items.order(:id).pluck(:id, :priority, :position)
        submitted = positions
        submitted.first[attribute] = value

        patch reorder_list_list_items_path(@list), params: { positions: submitted }, as: :json

        assert_response :unprocessable_entity
        assert_equal before, @list.list_items.order(:id).pluck(:id, :priority, :position)
      end
    end
  end

  %i[id position].each do |attribute|
    test "reorder rejects a valid #{attribute} with trailing garbage" do
      before = @list.list_items.order(:id).pluck(:id, :priority, :position)
      submitted = positions
      submitted.first[attribute] = "#{submitted.first[attribute]}oops"

      patch reorder_list_list_items_path(@list), params: { positions: submitted }, as: :json

      assert_response :unprocessable_entity
      assert_equal before, @list.list_items.order(:id).pluck(:id, :priority, :position)
    end
  end

  test "reorder accepts base ten IDs and positions with whitespace signs and underscores" do
    submitted = positions

    submitted.each do |entry|
      entry[:id] = " +#{entry[:id].to_s.chars.join("_")} "
      entry[:position] = " #{entry[:position]} "
    end

    patch reorder_list_list_items_path(@list), params: { positions: submitted }, as: :json

    assert_response :no_content

    submitted.each do |entry|
      assert_equal entry[:position].to_i, @list.list_items.find(Integer(entry[:id], 10)).position
    end
  end

  [ nil, [], {}, "invalid", [ nil ], [ "invalid" ] ].each do |payload|
    test "reorder rejects invalid positions shape #{payload.inspect}" do
      before = @list.list_items.order(:id).pluck(:id, :priority, :position)

      patch reorder_list_list_items_path(@list), params: { positions: payload }, as: :json

      assert_response :unprocessable_entity
      assert_equal before, @list.list_items.order(:id).pluck(:id, :priority, :position)
    end
  end

  private

  def positions
    @list.list_items.order(:id).each_with_index.map do |item, position|
      { id: item.id, priority: "medium", position: position }
    end
  end
end
