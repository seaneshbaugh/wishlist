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
      fill_in "Name", with: "50mm Lens"

      click_button "Add Item"
    end

    within "#list-items" do
      assert_text "50mm Lens"
    end
  end

  test "user creates a list item using the bottom form" do
    visit list_path(@list)

    within "#new-list-item-form-bottom" do
      fill_in "Name", with: "50mm Lens"

      click_button "Add Item"
    end

    within "#list-items" do
      assert_text "50mm Lens"
    end
  end

  test "filling out a draft in the top form and then creating an item in the bottom form does not clear the top form" do
    visit list_path(@list)

    within "#new-list-item-form-top" do
      fill_in "Name", with: "50mm Lens"
    end

    within "#new-list-item-form-bottom" do
      fill_in "Name", with: "Baseball"

      click_button "Add Item"
    end

    within "#list-items" do
      assert_no_text "50mm Lens"
      assert_text "Baseball"
    end

    within "#new-list-item-form-bottom" do
      assert page.has_field?("Name", with: "")
    end

    within "#new-list-item-form-top" do
      assert page.has_field?("Name", with: "50mm Lens")
    end
  end

  test "filling out a draft in the bottom form and then creating an item in the top form does not clear the bottom form" do
    visit list_path(@list)

    within "#new-list-item-form-bottom" do
      fill_in "Name", with: "50mm Lens"
    end

    within "#new-list-item-form-top" do
      fill_in "Name", with: "Baseball"

      click_button "Add Item"
    end

    within "#list-items" do
      assert_no_text "50mm Lens"
      assert_text "Baseball"
    end

    within "#new-list-item-form-top" do
      assert page.has_field?("Name", with: "")
    end

    within "#new-list-item-form-bottom" do
      assert page.has_field?("Name", with: "50mm Lens")
    end
  end

  test "user sees validation errors when creating an invalid list item" do
    visit list_path(@list)

    within "#new-list-item-form-top" do
      fill_in "Name", with: ""

      click_button "Add Item"
    end

    assert_text "prevented this item from being saved"
    assert_text "Name can't be blank"
  end

  test "user edits a list item" do
    list_item = list_items(:football)

    visit list_path(@list)

    within "[data-id='#{list_item.id}']" do
      click_button "Edit"

      fill_in "Notes", with: "A nice pigskin"

      click_button "Save Changes"

      assert_text "A nice pigskin"
    end
  end

  test "user sees validation errors when editing an invalid list item" do
    list_item = list_items(:football)

    visit list_path(@list)

    within "[data-id='#{list_item.id}']" do
      click_button "Edit"

      fill_in "Name", with: ""

      click_button "Save Changes"

      assert_text "prevented this item from being saved"
      assert_text "Name can't be blank"
    end
  end

  test "user deletes a list item" do
    list_item = list_items(:football)

    visit list_path(@list)

    within "[data-id='#{list_item.id}']" do
      accept_confirm "Delete this item?" do
        click_button "Delete #{list_item.name}"
      end
    end

    assert_no_text list_item.name

    assert_not ListItem.exists?(list_item.id)
  end

  test "user reorders list items" do
    first = list_items(:football)
    second = list_items(:lucky_cat)

    first.update!(priority: 0, position: 0)
    second.update!(priority: 0, position: 1)

    visit list_path(@list)

    first_row = find("[data-id='#{first.id}']")
    second_row = find("[data-id='#{second.id}']")

    first_row.find("[data-reorder-handle]").drag_to(second_row)

    assert_selector("[data-reorder-target='item']:first-child[data-id='#{second.id}']")

    first.reload
    second.reload

    assert_equal 1, first.position
    assert_equal 0, second.position
  end
end
