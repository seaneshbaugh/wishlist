require "test_helper"

class RegistrationNotificationJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    @original_sender = ENV["DEVISE_MAILER_SENDER"]
    @original_recipient = ENV["REGISTRATION_NOTIFICATION_EMAIL"]
    ENV["DEVISE_MAILER_SENDER"] = "Wishlist <wishlist@example.com>"
  end

  teardown do
    ENV["DEVISE_MAILER_SENDER"] = @original_sender
    ENV["REGISTRATION_NOTIFICATION_EMAIL"] = @original_recipient
  end

  test "notifies the configured account independently of the sender" do
    ENV["REGISTRATION_NOTIFICATION_EMAIL"] = " SEAN@SEANESHBAUGH.COM "

    assert_emails 1 do
      RegistrationNotificationJob.perform_now(users(:casie))
    end

    email = ActionMailer::Base.deliveries.last
    assert_equal [ users(:sean).email ], email.to
    assert_equal [ "wishlist@example.com" ], email.from
    assert_equal "Wishlist", email[:from].display_names.first
  end

  test "does not send alerts when no recipient is configured" do
    ENV.delete("REGISTRATION_NOTIFICATION_EMAIL")

    assert_no_emails do
      RegistrationNotificationJob.perform_now(users(:casie))
    end
  end

  test "does not send alerts to an address without an account" do
    ENV["REGISTRATION_NOTIFICATION_EMAIL"] = "missing@example.com"

    assert_no_emails do
      RegistrationNotificationJob.perform_now(users(:casie))
    end
  end
end
