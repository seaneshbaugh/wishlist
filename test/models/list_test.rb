require "test_helper"

class ListTest < ActiveSupport::TestCase
  test "first list starts at zero regardless of other owners lists" do
    lists(:christmas_list).update!(position: 20)

    list = users(:casie).lists.create!(name: "First wishlist", description: "")

    assert_equal 0, list.reload.position
  end

  test "new lists append after the owners highest position" do
    lists(:birthday_list).update!(position: 7)

    owner = users(:sean)
    first = owner.lists.create!(name: "New wishlist", description: "")
    second = owner.lists.create!(name: "Another wishlist", description: "")

    assert_equal 8, first.reload.position
    assert_equal 9, second.reload.position
  end

  test "creation overwrites an explicitly supplied position" do
    list = users(:sean).lists.create!(name: "New wishlist", description: "", position: 99)

    assert_equal 2, list.reload.position
  end

  test "validation before saving recalculates the append position" do
    owner = users(:sean)
    list = owner.lists.build(name: "New wishlist", description: "")

    assert list.valid?
    assert_equal 2, list.position

    owner.lists.create!(name: "Intervening wishlist", description: "")

    list.save!

    assert_equal 3, list.reload.position
  end

  test "updates preserve position and allow explicit reordering" do
    list = lists(:christmas_list)

    list.update!(description: "Updated")

    assert_equal 0, list.reload.position

    list.update!(position: 5)

    assert_equal 5, list.reload.position
  end

  test "missing owner returns validation errors without raising" do
    list = List.new(name: "New wishlist", description: "")

    assert_not list.valid?
    assert list.errors.of_kind?(:user, :blank)
  end
end
