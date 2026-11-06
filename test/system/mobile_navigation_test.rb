require "application_system_test_case"

class MobileNavigationTest < ApplicationSystemTestCase
  setup do
    confirm_and_sign_in users(:sean)
  end

  teardown do
    page.current_window.resize_to(1400, 1400)
  end

  test "mobile menu stays below a stable branding row at narrow and wider mobile widths" do
    [ 500, 700 ].each do |width|
      page.current_window.resize_to(width, 900)

      visit lists_path

      assert_no_selector "#mobile-menu"

      before = navigation_bounds

      assert_in_delta before["brand"]["center"], before["button"]["center"], 1
      assert_operator before["button"]["left"], :>, before["brand"]["right"]

      page.save_screenshot(Rails.root.join("tmp/screenshots/mobile-navigation-#{width}-closed.png"))

      click_button "Toggle navigation"

      assert_selector "#mobile-menu"
      assert_selector "#mobile-menu-button[aria-expanded='true']"

      after = navigation_bounds

      assert_in_delta before["brand"]["top"], after["brand"]["top"], 1
      assert_in_delta before["button"]["top"], after["button"]["top"], 1
      assert_operator after["menu"]["top"], :>=, after["button"]["bottom"]
      assert_operator after["main"]["top"], :>=, after["menu"]["bottom"]
      assert_equal "center", page.evaluate_script("getComputedStyle(document.querySelector('#mobile-menu a')).textAlign")
      assert_equal "rgb(255, 255, 255)", page.evaluate_script("getComputedStyle(document.querySelector('#mobile-menu')).backgroundColor")

      page.save_screenshot(Rails.root.join("tmp/screenshots/mobile-navigation-#{width}-open.png"))

      within "#mobile-menu" do
        find_link("Friends").send_keys(:escape)
      end

      assert_no_selector "#mobile-menu"
      assert_selector "#mobile-menu-button[aria-expanded='false']:focus"

      click_button "Toggle navigation"

      assert_selector "#mobile-menu"

      click_button "Toggle navigation"

      assert_no_selector "#mobile-menu"
    end
  end

  test "mobile navigation closes after Turbo navigation and history restoration" do
    page.current_window.resize_to(700, 900)

    visit lists_path

    click_button "Toggle navigation"

    assert_selector "#mobile-menu"

    within "#mobile-menu" do
      click_link "Friends"
    end

    assert_current_path friends_path
    assert_no_selector "#mobile-menu"

    page.go_back

    assert_current_path lists_path

    assert_no_selector "#mobile-menu"

    click_button "Toggle navigation"

    assert_selector "#mobile-menu"

    click_button "Toggle navigation"

    assert_no_selector "#mobile-menu"
  end

  test "desktop keeps inline navigation and hides the mobile controls" do
    page.current_window.resize_to(1000, 900)

    visit lists_path

    assert_no_button "Toggle navigation"
    assert_no_selector "#mobile-menu"

    within "[data-controller='mobile-menu']" do
      assert_link "My Lists"
      assert_link "Friends"
      assert_text "sean"
    end

    page.save_screenshot(Rails.root.join("tmp/screenshots/mobile-navigation-desktop.png"))
  end

  private

  def navigation_bounds
    page.evaluate_script(<<~JS)
      Object.fromEntries(Object.entries({
        brand: 'header a', button: '#mobile-menu-button', menu: '#mobile-menu', main: 'main'
      }).map(([name, selector]) => {
        const rect = document.querySelector(selector).getBoundingClientRect();
        return [name, {top: rect.top, bottom: rect.bottom, left: rect.left, right: rect.right,
          center: rect.top + rect.height / 2}];
      }))
    JS
  end
end
