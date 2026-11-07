# Run explicitly with:
# docker compose exec -T web bundle exec rails test script/capture_help_screenshots.rb
require "application_system_test_case"

raise "Help screenshots must use the test environment" unless Rails.env.test?

class HelpScreenshotsCapture < ApplicationSystemTestCase
  test "capture the help illustrations from real browser workflows" do
    alex = create_example_user("alex_example", "alex@example.com")
    jordan = create_example_user("jordan_example", "jordan@example.com")
    confirm_and_sign_in alex
    page.current_window.resize_to(1120, 1100)
    FileUtils.mkdir_p(Rails.root.join("app/assets/images/help"))

    visit invitations_path
    fill_in "Email address", with: "morgan@example.com"
    click_button "Send invitation"
    assert_text I18n.t("invitations.create.success")
    visit invitations_path
    capture("invitations", "main")

    visit friends_path
    fill_in "Friend's email address", with: jordan.email
    click_button "Send friend request"
    assert_text I18n.t("friendships.create.success")
    sign_out alex
    confirm_and_sign_in jordan
    visit requests_friendships_path
    assert_button "Accept alex_example"
    capture("friend-requests", "#incoming-friend-requests")
    click_button "Accept alex_example"
    assert_text "Friend request accepted."

    sign_out jordan
    confirm_and_sign_in alex
    visit lists_path
    click_link "New List"
    fill_in "Name", with: "Winter gift ideas"
    fill_in "Description", with: "A few ideas for the holidays."
    choose "Friends"
    page.current_window.resize_to(1120, 1400)
    page.execute_script("window.scrollTo(0, 0)")
    capture("create-list", "main form")
    page.current_window.resize_to(1120, 1100)
    click_button "Create List"
    assert_selector "h1", text: "Winter gift ideas"
    list = alex.lists.find_by!(name: "Winter gift ideas")

    within "#new-list-item-form-top" do
      fill_in "Name", with: "Reading lamp"
      select "Highest", from: "Priority"
      fill_in "Quantity", with: 1
      fill_in "Price", with: "35.00"
      fill_in "Notes", with: "A warm light for the bedside table."
      fill_in "list_item_url", with: "https://shop.example.com/products/reading-lamp"
      click_button "Add Item"
    end
    assert_selector "#list-items", text: "Reading lamp"

    within "#new-list-item-form-top" do
      fill_in "Name", with: "Hardcover notebook"
      select "Medium", from: "Priority"
      fill_in "Quantity", with: 2
      fill_in "Price", with: "12.00"
      fill_in "Notes", with: "Plain pages, please."
      fill_in "list_item_url", with: "https://shop.example.com/products/notebook"
      click_button "Add Item"
    end
    assert_selector "#list-items", text: "Hardcover notebook"
    visit list_path(list)
    capture("list-items", "#list-items")

    sign_out alex
    confirm_and_sign_in jordan
    visit friends_path
    click_link "alex_example"
    click_link "Winter gift ideas"
    click_button "Purchase Reading lamp"
    lamp = list.list_items.find_by!(name: "Reading lamp")
    within "#purchase_form_list_item_#{lamp.id}" do
      fill_in "Quantity", with: 1
      fill_in "Purchase Price", with: "32.00"
      fill_in "Purchased From", with: "Local home store"
      reveal_year = Time.current.year
      reveal_year += 1 if Time.current >= Time.zone.local(reveal_year, 12, 25, 9)
      fill_in "Reveal Date & Time", with: Time.zone.local(reveal_year, 12, 25, 9)
      fill_in "Notes", with: "Wrapped and ready."
    end
    capture("purchase", "#purchase_form_list_item_#{lamp.id}")
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  private

  def create_example_user(username, email)
    User.new(username: username, email: email, password: "example-password-123").tap do |user|
      user.skip_confirmation!
      user.save!
    end
  end

  def capture(name, selector)
    find(selector).native.save_screenshot(Rails.root.join("app/assets/images/help/#{name}.png"))
  end
end
