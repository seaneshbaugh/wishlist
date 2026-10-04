require "application_system_test_case"

class ListsTest < ApplicationSystemTestCase
  setup do
    @user = users(:sean)
    confirm_and_sign_in @user
  end

  test "user creates a list" do
    visit new_list_path

    fill_in "Name", with: "Birthday Ideas"
    fill_in "Description", with: "Things I might want for my birthday"

    choose "Public"

    click_button "Create List"

    assert_current_path list_path(List.last)

    assert_text "Birthday Ideas"
    assert_text "Things I might want for my birthday"
    assert_text "List was successfully created."
  end

  test "user sees validation errors when creating an invalid list" do
    visit new_list_path

    fill_in "Name", with: ""

    click_button "Create List"

    assert_current_path new_list_path

    assert_text "Error creating list."
    assert_text "Name can't be blank"
    assert_text "Name is too short"
  end

  test "user edits a list" do
    list = lists(:christmas_list)

    visit edit_list_path(list)

    fill_in "Description", with: "Ho Ho Ho"

    click_button "Save Changes"

    assert_current_path edit_list_path(list)

    assert_text "Ho Ho Ho"
  end
end
