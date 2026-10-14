require "application_system_test_case"

class PurchasesTest < ApplicationSystemTestCase
  setup do
    @owner = users(:sean)
    @purchaser = users(:casie)
    @other_viewer = users(:amelia)
    @list = lists(:christmas_list)
    @item = list_items(:paint_brush)
    @reveal_at = 1.month.from_now.change(sec: 0)

    confirm_and_sign_in @purchaser
  end

  test "user purchases an item and reopens its saved purchase" do
    visit_list

    open_purchase

    within purchase_form do
      fill_in "Quantity", with: 2
      fill_in "Purchase Price", with: "25.50"
      fill_in "Purchased From", with: "Art shop"
      fill_in "Notes", with: "Gift wrapped"
      choose "Remain anonymous"
      fill_in "Reveal Date & Time", with: @reveal_at
      click_button "Mark as Purchased"
    end

    wait_for_purchase

    purchase = @item.purchases.reload.sole

    assert_equal @purchaser, purchase.user
    assert_equal 2, purchase.quantity
    assert_equal BigDecimal("25.50"), purchase.price
    assert purchase.anonymous?
    assert_equal @reveal_at.to_i, purchase.reveal_at.to_i

    open_purchase

    within purchase_form do
      assert_field "Quantity", with: "2"
      assert_field "Purchased From", with: "Art shop"
      assert_field "Notes", with: "Gift wrapped"
      assert_checked_field "Remain anonymous"
      assert_button "Save Purchase"
    end
  end

  test "user edits an unrevealed purchase without creating another" do
    purchase = create_purchase(notes: "Original")

    visit_list

    open_purchase

    within purchase_form do
      assert_field "Notes", with: "Original"
      fill_in "Notes", with: "Updated"
      click_button "Save Purchase"
    end

    wait_for_purchase

    assert_equal "Updated", purchase.reload.notes
    assert_equal [ purchase.id ], @item.purchases.pluck(:id)
  end

  test "blank reveal date shows errors and the replaced form can be resubmitted" do
    other_item = list_items(:football)

    visit_list

    open_purchase(other_item)

    within purchase_form(other_item) do
      fill_in "Notes", with: "Another draft"
    end

    open_purchase

    within purchase_form do
      fill_in "Notes", with: "Keep this value"
      click_button "Mark as Purchased"

      assert_text "Reveal At can't be blank"
      assert_field "Notes", with: "Keep this value"
    end

    assert_empty @item.purchases.reload

    within purchase_form(other_item) do
      assert_field "Notes", with: "Another draft"
    end

    within purchase_form do
      fill_in "Reveal Date & Time", with: @reveal_at
      click_button "Mark as Purchased"
    end

    wait_for_purchase

    assert_equal "Keep this value", @item.purchases.reload.sole.notes
  end

  test "invalid creation exceeding remaining quantity can be corrected" do
    create_purchase(user: @other_viewer, quantity: 2)

    visit_list

    open_purchase

    within purchase_form do
      fill_in "Quantity", with: 2
      fill_in "Reveal Date & Time", with: @reveal_at
      click_button "Mark as Purchased"

      assert_text "prevented this purchase from being saved"
      assert_field "Quantity", with: "2"
    end

    assert_equal 1, @item.purchases.count

    within purchase_form do
      fill_in "Quantity", with: 1
      click_button "Mark as Purchased"
    end

    wait_for_purchase

    assert_equal 2, @item.purchases.count
  end

  test "invalid update preserves the saved purchase and can be corrected" do
    purchase = create_purchase(notes: "Original")

    create_purchase(user: @other_viewer, quantity: 2)

    visit_list

    open_purchase

    within purchase_form do
      fill_in "Quantity", with: 2
      fill_in "Notes", with: "Updated"
      click_button "Save Purchase"

      assert_text "prevented this purchase from being saved"
      assert_field "Notes", with: "Updated"
    end

    assert_equal 1, purchase.reload.quantity
    assert_equal "Original", purchase.notes

    within purchase_form do
      fill_in "Quantity", with: 1
      click_button "Save Purchase"
    end

    wait_for_purchase

    assert_equal "Updated", purchase.reload.notes
    assert_equal 2, @item.purchases.count
  end

  test "user deletes an unrevealed purchase and can create again" do
    purchase = create_purchase

    visit_list

    within item_row do
      accept_confirm "Delete this purchase?" do
        click_button "Delete purchase"
      end

      assert_no_button "Delete purchase"
    end

    assert_not Purchase.exists?(purchase.id)

    # Revisit to verify the persisted create state after deletion.
    visit_list

    open_purchase

    within purchase_form do
      assert_button "Mark as Purchased"
    end
  end

  test "canceling a new purchase returns to the item without saving" do
    visit_list

    open_purchase

    within purchase_form do
      fill_in "Notes", with: "Unsaved"
      click_button "Cancel"
    end

    within item_row do
      assert_button "Purchase #{@item.name}"
      assert_no_button "Mark as Purchased"
    end

    assert_empty @item.purchases.reload
  end

  test "canceling purchase edits leaves the saved purchase unchanged" do
    purchase = create_purchase(notes: "Original")

    visit_list

    open_purchase

    within purchase_form do
      fill_in "Notes", with: "Unsaved"
      click_button "Cancel"
    end

    within item_row do
      assert_button "Purchase #{@item.name}"
      assert_no_button "Save Purchase"
    end

    assert_equal "Original", purchase.reload.notes
  end

  test "buying the final quantity hides the item from another viewer but allows purchaser edits" do
    visit_list

    open_purchase

    within purchase_form do
      fill_in "Quantity", with: 3
      fill_in "Reveal Date & Time", with: @reveal_at
      click_button "Mark as Purchased"
    end

    wait_for_purchase

    open_purchase

    within purchase_form do
      assert_button "Save Purchase"
    end

    switch_user(@other_viewer)

    assert_no_selector item_row
  end

  test "deleting a purchase restores availability for another viewer" do
    create_purchase(quantity: 3)

    switch_user(@other_viewer)

    assert_no_selector item_row

    switch_user(@purchaser)

    within item_row do
      accept_confirm "Delete this purchase?" do
        click_button "Delete purchase"
      end

      assert_no_button "Delete purchase"
    end

    switch_user(@other_viewer)

    assert_selector item_row
  end

  test "user creates a new purchase after a historical purchase reveals" do
    historical = create_purchase(reveal_at: 1.day.ago)

    visit_list

    open_purchase

    within purchase_form do
      assert_button "Mark as Purchased"

      fill_in "Reveal Date & Time", with: @reveal_at
      click_button "Mark as Purchased"
    end

    wait_for_purchase

    assert_equal 2, @item.purchases.count
    assert historical.reload.revealed?
    assert_equal 1, historical.quantity
    assert_equal 1, @item.purchases.unrevealed.count
  end

  test "owner sees only revealed purchase quantities after the reveal time" do
    reveal_at = 2.days.from_now.change(sec: 0)

    create_purchase(quantity: 2, reveal_at: reveal_at)

    switch_user(@owner)

    within item_row do
      assert_no_text "Purchased"
      assert_no_button "Purchase #{@item.name}"
    end

    travel_to reveal_at + 1.minute do
      # Advancing time also expires Devise's existing session.
      switch_user(@owner)

      within item_row do
        assert_text "Purchased"
        assert_text "2 of 3"
      end
    end
  end

  private

  def visit_list
    visit user_list_path(@owner, @list)
  end

  def switch_user(user)
    sign_out @purchaser
    sign_out @owner
    sign_out @other_viewer
    confirm_and_sign_in user
    visit_list
  end

  def create_purchase(user: @purchaser, **attributes)
    @item.purchases.create!({ user: user, quantity: 1, reveal_at: @reveal_at }.merge(attributes))
  end

  def item_row(item = @item)
    "[data-controller='list-item'][data-id='#{item.id}']"
  end

  def purchase_form(item = @item)
    "#purchase_form_list_item_#{item.id}"
  end

  def open_purchase(item = @item)
    within item_row(item) do
      click_button "Purchase #{item.name}"
    end
  end

  def wait_for_purchase
    within item_row do
      assert_button "Delete purchase"
      assert_no_button "Mark as Purchased"
      assert_no_button "Save Purchase"
    end
  end
end
