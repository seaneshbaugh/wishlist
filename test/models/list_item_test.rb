require "test_helper"

class ListItemTest < ActiveSupport::TestCase
  setup do
    @item = list_items(:paint_brush)
    @owner = users(:sean)
    @purchaser = users(:casie)
    @viewer = users(:amelia)
  end

  test "owner sees hidden and fully purchased items" do
    purchase(quantity: 3)

    @item.update!(visible: false)

    assert ListItem.visible_to(@owner).exists?(@item.id)
    assert_not ListItem.visible_to(@purchaser).exists?(@item.id)
    assert_not ListItem.visible_to(@viewer).exists?(@item.id)
  end

  test "visible items remain available until all requested quantity is purchased" do
    purchase(quantity: 2)

    assert ListItem.visible_to(@viewer).exists?(@item.id)

    purchase(user: @viewer)

    outsider = User.create!(username: "outsider", email: "outsider@example.com", password: "password123")

    assert_not ListItem.visible_to(outsider).exists?(@item.id)
    assert ListItem.visible_to(@purchaser).exists?(@item.id)
    assert ListItem.visible_to(@viewer).exists?(@item.id)
  end

  test "revealed historical purchases preserve visibility of a fulfilled item" do
    purchase(quantity: 3, reveal_at: 1.day.ago)

    assert ListItem.visible_to(@purchaser).exists?(@item.id)
    assert_not ListItem.visible_to(@viewer).exists?(@item.id)
  end

  test "hidden items are not visible to non-owners even with quantity remaining" do
    @item.update!(visible: false)

    assert_not ListItem.visible_to(@viewer).exists?(@item.id)
  end

  test "purchases of a different item do not affect visibility" do
    other = list_items(:football)

    other.purchases.create!(user: @purchaser, quantity: 1, reveal_at: 1.day.from_now)

    assert ListItem.visible_to(@viewer).exists?(@item.id)
    assert_not ListItem.visible_to(@viewer).exists?(other.id)
  end

  test "deleting a purchase restores visibility for a non-purchaser" do
    reservation = purchase(quantity: 3)

    assert_not ListItem.visible_to(@viewer).exists?(@item.id)

    reservation.destroy!

    assert ListItem.visible_to(@viewer).exists?(@item.id)
  end

  test "purchase helpers distinguish historical purchases users and unrevealed purchases" do
    historical = purchase(reveal_at: 1.day.ago)
    current = purchase
    other = purchase(user: @viewer)

    @item.purchases.reload

    assert_equal [ historical.id, current.id ].sort, @item.purchases_for(@purchaser).map(&:id).sort
    assert_equal current, @item.unrevealed_purchase_for(@purchaser)
    assert_equal other, @item.unrevealed_purchase_for(@viewer)
    assert_empty @item.purchases_for(@owner)
    assert_nil @item.unrevealed_purchase_for(@owner)
  end

  test "revealed helpers count only purchases at or before the reveal boundary" do
    freeze_time do
      purchase(reveal_at: Time.current)
      purchase(user: @viewer, reveal_at: 1.second.from_now, quantity: 2)

      @item.purchases.reload

      assert @item.revealed_purchase?
      assert_equal 1, @item.revealed_purchase_quantity
      assert_nil @item.unrevealed_purchase_for(@purchaser)
    end
  end

  test "revealed helpers return false and zero without revealed purchases" do
    assert_not @item.revealed_purchase?
    assert_equal 0, @item.revealed_purchase_quantity

    purchase

    @item.purchases.reload

    assert_not @item.revealed_purchase?
    assert_equal 0, @item.revealed_purchase_quantity
  end

  test "first item in a priority starts at zero independently of other groups and lists" do
    @item.update!(position: 20)

    lists(:birthday_list).list_items.create!(name: "Other item", priority: :low).update!(position: 99)

    item = @item.list.list_items.create!(name: "New item", priority: :low)

    assert_equal 0, item.reload.position
  end

  test "new items append after the highest position within their list and priority" do
    @item.update!(position: 7)

    first = @item.list.list_items.create!(name: "First addition", priority: :medium)
    second = @item.list.list_items.create!(name: "Second addition", priority: :medium)

    assert_equal 8, first.reload.position
    assert_equal 9, second.reload.position
  end

  test "creation overwrites an explicitly supplied item position" do
    item = @item.list.list_items.create!(name: "New item", priority: :medium, position: 99)

    assert_equal 1, item.reload.position
  end

  test "item validation before saving recalculates position for the selected priority" do
    list = @item.list
    item = list.list_items.build(name: "New item", priority: :medium)

    assert item.valid?
    assert_equal 1, item.position

    list.list_items.create!(name: "Intervening item", priority: :high)

    item.priority = :high

    item.save!

    assert_equal "high", item.reload.priority
    assert_equal 2, item.position
  end

  test "item updates preserve position and allow explicit reordering" do
    @item.update!(position: 5)
    @item.update!(notes: "Updated")

    assert_equal 5, @item.reload.position

    @item.update!(priority: :high, position: 2)

    assert_equal "high", @item.reload.priority
    assert_equal 2, @item.position
  end

  test "missing list returns validation errors without raising" do
    item = ListItem.new(name: "New item")

    assert_not item.valid?
    assert item.errors.of_kind?(:list, :blank)
  end

  private

  def purchase(**attributes)
    @item.purchases.create!({ user: @purchaser, quantity: 1, reveal_at: 1.day.from_now }.merge(attributes))
  end
end
