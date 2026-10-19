require "test_helper"

class PurchaseTest < ActiveSupport::TestCase
  setup do
    @item = list_items(:paint_brush)
    @owner = users(:sean)
    @purchaser = users(:casie)
    @other = users(:amelia)
  end

  test "predicate and scopes agree immediately before at and after reveal" do
    freeze_time

    reservation = purchase(reveal_at: 1.minute.from_now)
    reveal_at = reservation.reveal_at

    travel_to reveal_at - 1.second do
      assert_not reservation.revealed?
      assert Purchase.unrevealed.exists?(reservation.id)
      assert_not Purchase.revealed.exists?(reservation.id)
    end

    [ reveal_at, reveal_at + 1.second ].each do |time|
      travel_to time do
        assert reservation.revealed?
        assert Purchase.revealed.exists?(reservation.id)
        assert_not Purchase.unrevealed.exists?(reservation.id)
      end
    end
  end

  test "permissions change at reveal for purchaser owner and other users" do
    reservation = purchase

    assert reservation.editable_by?(@purchaser)
    assert reservation.deletable_by?(@purchaser)
    assert_not reservation.editable_by?(@owner)
    assert_not reservation.deletable_by?(@owner)
    assert_not reservation.editable_by?(@other)
    assert_not reservation.deletable_by?(@other)

    travel_to reservation.reveal_at do
      assert_not reservation.editable_by?(@purchaser)
      assert_not reservation.deletable_by?(@purchaser)
      assert_not reservation.editable_by?(@owner)
      assert reservation.deletable_by?(@owner)
      assert_not reservation.editable_by?(@other)
      assert_not reservation.deletable_by?(@other)
    end
  end

  test "missing reveal date is invalid without raising" do
    reservation = build_purchase(reveal_at: nil)

    assert_not reservation.revealed?
    assert_not reservation.valid?
    assert reservation.errors.of_kind?(:reveal_at, :blank)
  end

  test "purchase may use exactly the remaining quantity but no more" do
    purchase(user: @other, quantity: 2)

    reservation = build_purchase(quantity: 1)

    assert reservation.valid?, reservation.errors.full_messages.to_sentence

    reservation.quantity = 2

    assert_not reservation.valid?
    assert reservation.errors.of_kind?(:quantity, :exceeds_remaining_quantity)
  end

  test "revealed purchases consume quantity and unrelated items do not" do
    purchase(user: @other, quantity: 2, reveal_at: 1.day.ago)

    list_items(:football).purchases.create!(user: @purchaser, quantity: 1, reveal_at: 1.day.from_now)

    reservation = build_purchase(quantity: 1)

    assert reservation.valid?, reservation.errors.full_messages.to_sentence

    reservation.quantity = 2

    assert_not reservation.valid?
    assert reservation.errors.of_kind?(:quantity, :exceeds_remaining_quantity)
  end

  test "quantity updates exclude the purchase itself from the total" do
    reservation = purchase(quantity: 2)

    purchase(user: @other)

    assert reservation.valid?, reservation.errors.full_messages.to_sentence

    reservation.quantity = 1

    assert reservation.save

    reservation.quantity = 3

    assert_not reservation.save
    assert reservation.errors.of_kind?(:quantity, :exceeds_remaining_quantity)
    assert_equal 1, reservation.reload.quantity
  end

  test "deletion frees quantity for a new purchase" do
    reservation = purchase(user: @other, quantity: 3)
    candidate = build_purchase

    assert_not candidate.valid?

    reservation.destroy!

    assert candidate.valid?, candidate.errors.full_messages.to_sentence
  end

  [ nil, 0, -1, 1.5, "invalid" ].each do |quantity|
    test "quantity #{quantity.inspect} is invalid" do
      reservation = build_purchase(quantity: quantity)

      assert_not reservation.valid?
      assert reservation.errors[:quantity].any?
    end
  end

  test "one user cannot have two unrevealed purchases for an item" do
    purchase

    duplicate = build_purchase

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:base, :more_than_one_remaining_purchase)
  end

  test "an existing unrevealed purchase can be updated without matching itself" do
    reservation = purchase
    reservation.notes = "Gift wrapped"

    assert reservation.save, reservation.errors.full_messages.to_sentence
    assert_equal "Gift wrapped", reservation.reload.notes
  end

  test "unrevealed uniqueness is scoped to both purchaser and item" do
    purchase

    other_user = build_purchase(user: @other)
    other_item = build_purchase(list_item: list_items(:football))

    assert other_user.save, other_user.errors.full_messages.to_sentence
    assert other_item.save, other_item.errors.full_messages.to_sentence
  end

  test "multiple historical purchases and a current purchase coexist" do
    first = purchase(reveal_at: 2.days.ago)
    second = purchase(reveal_at: 1.day.ago)
    current = purchase

    assert_equal [ first.id, second.id, current.id ].sort, @item.purchases.pluck(:id).sort
    assert_equal 2, @item.purchases.revealed.count
    assert_equal 1, @item.purchases.unrevealed.count
  end

  test "a purchase revealing now permits a new unrevealed purchase" do
    reservation = purchase

    travel_to reservation.reveal_at do
      candidate = build_purchase

      assert candidate.save, candidate.errors.full_messages.to_sentence
    end
  end

  test "rescheduling a historical purchase cannot create two unrevealed purchases" do
    historical = purchase(reveal_at: 1.day.ago)

    purchase

    historical.reveal_at = 2.days.from_now

    assert_not historical.save
    assert historical.errors.of_kind?(:base, :more_than_one_remaining_purchase)
    assert historical.reload.revealed?
  end

  test "lowering requested quantity does not prevent unrelated purchase edits" do
    reservation = purchase(quantity: 2)

    purchase(user: @other)

    @item.update!(quantity: 1)

    assert reservation.update(notes: "Gift wrapped"), reservation.errors.full_messages.to_sentence
    assert_equal "Gift wrapped", reservation.reload.notes
    assert_equal 2, reservation.quantity
  end

  test "purchase quantity can decrease even when the total still exceeds the request" do
    reservation = purchase(quantity: 2)

    purchase(user: @other)

    @item.update!(quantity: 1)

    assert reservation.update(quantity: 1), reservation.errors.full_messages.to_sentence
    assert_equal 1, reservation.reload.quantity
    assert_equal 2, @item.purchases.sum(:quantity)
  end

  test "an overfulfilled item still rejects purchase increases and new purchases" do
    reservation = purchase(quantity: 2)

    purchase(user: @other)

    @item.update!(quantity: 1)

    assert_not reservation.update(quantity: 3)
    assert reservation.errors.of_kind?(:quantity, :exceeds_remaining_quantity)
    assert_equal 2, reservation.reload.quantity

    candidate = build_purchase(user: @owner)

    assert_not candidate.valid?
    assert candidate.errors.of_kind?(:quantity, :exceeds_remaining_quantity)
  end

  test "purchase quantity may increase when the resulting total fits the request" do
    reservation = purchase

    purchase(user: @other)

    assert reservation.update(quantity: 2), reservation.errors.full_messages.to_sentence
    assert_equal 2, reservation.reload.quantity
  end

  test "decreasing a purchase still requires a positive integer quantity" do
    reservation = purchase(quantity: 2)

    @item.update!(quantity: 1)

    [ nil, 0, -1, 1.5 ].each do |quantity|
      reservation.quantity = quantity

      assert_not reservation.valid?
      assert reservation.errors[:quantity].any?
    end

    assert_equal 2, reservation.reload.quantity
  end

  private

  def build_purchase(**attributes)
    Purchase.new({ list_item: @item, user: @purchaser, quantity: 1, reveal_at: 1.day.from_now.change(sec: 0) }.merge(attributes))
  end

  def purchase(**attributes)
    build_purchase(**attributes).tap(&:save!)
  end
end
