require "test_helper"

class RegistrationMailerTest < ActionMailer::TestCase
  test "new sign up message" do
    user = users(:sean)

    new_user = users(:casie)

    email = RegistrationMailer.notification_message(user, new_user).deliver

    assert_not ActionMailer::Base.deliveries.empty?

    assert_equal([ "sean@seaneshbaugh.com" ], email.to)

    assert_equal("casie@casieeshbaugh.com has created a Wishlist account.", email.subject)

    assert_includes(email.encoded, "<h1>New User Registration</h1>")
  end

  test "welcome message" do
    new_user = users(:casie)

    email = RegistrationMailer.welcome_message(new_user).deliver

    assert_not ActionMailer::Base.deliveries.empty?

    assert_equal([ "casie@casieeshbaugh.com" ], email.to)

    assert_equal("Welcome to Wishlist!", email.subject)

    assert_includes(email.encoded, "<p style=\"font-size: 20px; line-height: 24px\">Welcome to <a href=\"http://example.com/\">Wishlist</a>!</p>")
  end
end
