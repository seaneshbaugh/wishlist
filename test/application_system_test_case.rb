require "test_helper"

Capybara.server = :puma, { Silent: true }
Capybara.server_host = "0.0.0.0"
Capybara.server_port = 3001
Capybara.app_host = "http://web:3001"

Capybara.register_driver :remote_firefox do |app|
  options = Selenium::WebDriver::Firefox::Options.new
  options.add_argument("-headless")

  Capybara::Selenium::Driver.new(app, browser: :remote, url: "http://selenium:4444", options:)
end

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :remote_firefox, screen_size: [ 1400, 1400 ]
end
