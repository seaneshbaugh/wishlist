require "test_helper"

class RegistrationFlowTest < ActionDispatch::IntegrationTest
  test "registration, confirmation, and login" do
    get "/register"

    assert_response :success

    assert_no_emails

    perform_enqueued_jobs(only: RegistrationNotificationJob) do
      post "/register", params: { user: { username: "newuser", email: "newuser@test.com", password: "test123456", password_confirmation: "test123456" } }
    end

    assert_performed_jobs(1, only: RegistrationNotificationJob)

    assert_emails 2

    confirmation_instructions_email = ActionMailer::Base.deliveries.find { |email| email.subject == "Confirmation instructions" }

    assert_not_nil confirmation_instructions_email

    notification_email = ActionMailer::Base.deliveries.find { |email| email.subject.start_with?("newuser@test.com has created a Wishlist account") }

    assert_not_nil notification_email

    confirmation_link = Nokogiri::HTML.parse(confirmation_instructions_email.body.to_s).css("a[href*=\"confirm-registration?confirmation_token=\"]").first

    assert_not_nil confirmation_link

    confirmation_path = "/#{confirmation_link.attributes["href"].value.gsub(/\Ahttp:\/\/.+\//, '')}"

    perform_enqueued_jobs(only: RegistrationWelcomeJob) do
      get confirmation_path
    end

    assert_performed_jobs(1, only: RegistrationWelcomeJob)

    assert_emails 3

    user_welcome_email = ActionMailer::Base.deliveries.find { |email| email.subject.start_with?("Welcome to ") }

    assert_not_nil user_welcome_email

    assert_response :redirect

    follow_redirect!

    assert_response :success

    post "/login", params: { user: { username: "newuser", password: "test123456" } }

    assert_response :redirect

    follow_redirect!

    assert_response :success
  end
end
