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
    assert_selector "#list-item-summary", text: "3 items"

    open_purchase

    within "#purchase_form_list_item_#{@brush.id}" do
      fill_in "Notes", with: "Updated gift"
      fill_in "Reveal Date & Time", with: ""

      click_button "Save Purchase"

      assert_text "Reveal At can't be blank"
      assert_field "Notes", with: "Updated gift"

      fill_in "Reveal Date & Time", with: 1.month.from_now.change(sec: 0)

      click_button "Save Purchase"
    end

    within item_row(@brush) do
      assert_no_button "Save Purchase"
    end

    assert_equal "Updated gift", @brush.purchases.reload.sole.notes
    assert_sort "price_asc", [ @cat, @brush, @football ]
    assert_selector "#list-item-summary", text: "3 items"

    within item_row(@brush) do
      accept_confirm { click_button "Delete purchase" }

      assert_no_button "Delete purchase"
    end

    assert_sort "price_asc", [ @cat, @brush, @football ]
    assert_empty @brush.purchases.reload
    assert_selector "#list-item-summary", text: "3 items"

    page.go_back

    assert_priority
  end

  test "price ties retain priority order and unpriced items remain last" do
    @football.update!(price: nil)

    extra = @list.list_items.create!(name: "Another gift", price: @cat.price, priority: :lowest)

    visit friend_list_path(@owner, @list)

    select_sort "Price: low to high"

    assert_sort "price_asc", [ @cat, extra, @brush, @football ]

    within item_row(extra) do
      assert_text "Lowest priority"
    end

    select_sort "Price: high to low"

    assert_sort "price_desc", [ @brush, @cat, extra, @football ]
  end

  test "sorting and purchase forms remain usable at a narrow viewport" do
    original_size = page.current_window.size
    page.current_window.resize_to(500, 844)

    visit friend_list_path(@owner, @list, sort: "price_desc")

    assert_sort "price_desc", [ @football, @brush, @cat ]

    select_sort "Price: low to high"

    assert_sort "price_asc", [ @cat, @brush, @football ]
    assert_no_horizontal_overflow

    page.save_screenshot(Rails.root.join("tmp/screenshots/list-sorting-mobile.png"))

    open_purchase

    within "#purchase_form_list_item_#{@brush.id}" do
      assert_field "Quantity"
      assert_field "Reveal Date & Time"
      assert_button "Mark as Purchased"
      fill_in "Notes", with: "Mobile draft"
    end

    assert_no_horizontal_overflow

    page.save_screenshot(Rails.root.join("tmp/screenshots/list-sorting-mobile-purchase.png"))
  ensure
    page.current_window.resize_to(*original_size) if original_size
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

  def assert_no_horizontal_overflow
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"),
      "The page should fit the viewport without horizontal scrolling"
  end
end
