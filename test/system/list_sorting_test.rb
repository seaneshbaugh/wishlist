require "application_system_test_case"

class ListSortingBrowserTest < ApplicationSystemTestCase
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

  test "sorting uses Turbo navigation and browser history restores each selection" do
    visit friend_list_path(@owner, @list)

    page.execute_script("window.sortNavigationMarker = 'preserved'")

    select_sort "Price: low to high"

    assert_sort "price_asc", [ @cat, @brush, @football ]

    select_sort "Price: high to low"

    assert_sort "price_desc", [ @football, @brush, @cat ]

    page.go_back

    assert_sort "price_asc", [ @cat, @brush, @football ]

    page.go_back

    assert_priority

    page.go_forward

    assert_sort "price_asc", [ @cat, @brush, @football ]

    assert_equal "preserved", page.evaluate_script("window.sortNavigationMarker")

    page.refresh

    assert_sort "price_asc", [ @cat, @brush, @football ]

    select_sort "Priority"

    assert_priority

    visit friend_list_path(@owner, @list, sort: "price_desc")

    assert_sort "price_desc", [ @football, @brush, @cat ]
  end

  test "purchase validation create update and delete preserve sorting without extra history" do
    visit friend_list_path(@owner, @list)

    select_sort "Price: low to high"

    assert_sort "price_asc", [ @cat, @brush, @football ]

    open_purchase

    within "#purchase_form_list_item_#{@brush.id}" do
      fill_in "Notes", with: "Keep this draft"

      click_button "Mark as Purchased"
      assert_text "Reveal At can't be blank"
      assert_field "Notes", with: "Keep this draft"

      fill_in "Reveal Date & Time", with: 1.month.from_now.change(sec: 0)

      click_button "Mark as Purchased"
    end

    within item_row(@brush) do
      assert_button "Delete purchase"
      assert_no_button "Mark as Purchased"
    end

    assert_sort "price_asc", [ @cat, @brush, @football ]

    open_purchase

    within "#purchase_form_list_item_#{@brush.id}" do
      fill_in "Notes", with: "Updated gift"

      click_button "Save Purchase"
    end

    within item_row(@brush) do
      assert_no_button "Save Purchase"
    end

    assert_equal "Updated gift", @brush.purchases.reload.sole.notes
    assert_sort "price_asc", [ @cat, @brush, @football ]

    within item_row(@brush) do
      accept_confirm { click_button "Delete purchase" }

      assert_no_button "Delete purchase"
    end

    assert_sort "price_asc", [ @cat, @brush, @football ]
    assert_empty @brush.purchases.reload

    page.go_back

    assert_priority
  end

  private

  def item_row(item)
    "#list-items [data-controller='list-item'][data-id='#{item.id}']"
  end

  def open_purchase
    within(item_row(@brush)) { click_button "Purchase #{@brush.name}" }
  end

  def select_sort(label)
    select label, from: "Sort by"
  end

  def assert_sort(sort, items)
    assert_current_path friend_list_path(@owner, @list, sort: sort)
    assert_field "Sort by", with: sort
    assert_selector "#list-items > [data-controller='list-item']", count: items.size
    items.each_with_index do |item, index|
      assert_selector "#list-items > [data-controller='list-item']:nth-child(#{index + 1})[data-id='#{item.id}']"
    end
    assert_no_selector "#list-items section"
    assert_text "Highest priority"
  end

  def assert_priority
    assert_current_path friend_list_path(@owner, @list)
    assert_field "Sort by", with: ""
    assert_selector "#list-items section", count: 3
  end
end
