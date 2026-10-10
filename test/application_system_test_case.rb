require "test_helper"

Capybara.server = :puma, { Silent: true }
Capybara.server_host = "0.0.0.0"
Capybara.server_port = 3001
Capybara.app_host = "http://web:3001"
Capybara.enable_aria_label = true

Capybara.register_driver :remote_firefox do |app|
  options = Selenium::WebDriver::Firefox::Options.new
  options.add_argument("-headless")

  Capybara::Selenium::Driver.new(app, browser: :remote, url: "http://selenium:4444", options:)
end

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :remote_firefox, screen_size: [ 1400, 1400 ]

  def assert_eventually(timeout: Capybara.default_max_wait_time)
    Timeout.timeout(timeout) do
      loop do
        return if yield

        sleep 0.05
      end
    end
  rescue Timeout::Error
    flunk "condition was not met within #{timeout} seconds"
  end

  def capture_logs!
    page.execute_script(<<~JS)
      window.jsLogs = [];
      ["log", "error", "warn", "info"].forEach((level) => {
        const original = console[level];
        console[level] = function(...args) {
          window.jsLogs.push({ level, message: args.join(" ") });
          original.apply(console, args);
        };
      });
    JS
  end

  def clear_captured_logs!
    page.evaluate_script("window.jsLogs = []")
  end

  def captured_logs
    page.evaluate_script("window.jsLogs || []")
  end
end
