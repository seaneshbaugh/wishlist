require "application_system_test_case"

class PurchasesTest < ApplicationSystemTestCase
  setup do
    @user = users(:sean)
    @purchaser = users(:casie)
    confirm_and_sign_in @purchaser
    @list = lists(:christmas_list)
  end

  test "user purchases an item on another users list" do
    list_item = list_items(:football)

    visit user_list_path(@user, @list)

    within "[data-id='#{list_item.id}']" do
      click_button "Purchase #{list_item.name}"
    end

    within "#purchase_form_list_item_#{list_item.id}" do
      fill_in "Reveal Date & Time", with: 1.month.from_now.change(sec: 0)

      click_button "Mark as Purchased"
    end

    within "[data-id='#{list_item.id}']" do
      assert_button "Delete purchase"
    end

    assert list_item.reload.purchases_for(@purchaser).length == 1
  end

  test "user sees validation errors when creating an invalid purchase" do
    list_item = list_items(:football)

    visit user_list_path(@user, @list)

    within "[data-id='#{list_item.id}']" do
      click_button "Purchase #{list_item.name}"
    end

    within "#purchase_form_list_item_#{list_item.id}" do
      click_button "Mark as Purchased"

      assert_text "error prevented this purchase from being saved"
    end

    within "[data-id='#{list_item.id}']" do
      assert_no_button "Delete purchase"
    end

    assert list_item.reload.purchases_for(@purchaser).length == 0
  end
end
