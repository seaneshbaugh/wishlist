require "application_system_test_case"

class ListItemsTest < ApplicationSystemTestCase
  setup do
    @user = users(:sean)
    confirm_and_sign_in @user
    @list = lists(:christmas_list)
  end

  test "user creates a list item using the top form" do
    visit list_path(@list)

    within "#new-list-item-form-top" do
      fill_in "Name", with: "Football"
      click_button "Add Item"
    end

    within "#list-items" do
      assert_text "Football"
    end
  end

  test "user creates a list item using the bottom form" do
    visit list_path(@list)

    within "#new-list-item-form-bottom" do
      fill_in "Name", with: "Football"
      click_button "Add Item"
    end

    within "#list-items" do
      assert_text "Football"
    end
  end
end
