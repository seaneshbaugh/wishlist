require "application_system_test_case"

class HelpTest < ApplicationSystemTestCase
  test "help navigation screenshots and section links work on desktop and mobile" do
    visit new_user_session_path

    click_link "Help", exact: true

    assert_current_path help_path
    assert_selector "h1", text: "Using Wishlist"

    page.save_screenshot(Rails.root.join("tmp/screenshots/help-desktop.png"))

    all("figure img", count: 5).each do |screenshot|
      screenshot.execute_script("this.scrollIntoView({block: 'center'})")

      assert_eventually { screenshot.evaluate_script("this.complete && this.naturalWidth > 0") }
    end

    page.current_window.resize_to(500, 1000)

    visit help_path

    page.save_screenshot(Rails.root.join("tmp/screenshots/help-mobile.png"))

    within "nav[aria-label='Help sections']" do
      click_link "Marking items as purchased"
    end

    assert_current_path help_path
    assert_eventually { page.evaluate_script("window.location.hash") == "#purchases" }
    assert_selector "#purchases h2", text: "Marking items as purchased"
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    assert_operator page.evaluate_script("document.querySelector('#purchases').getBoundingClientRect().top"), :>=, 64
  ensure
    page.current_window.resize_to(1400, 1400)
  end
end
