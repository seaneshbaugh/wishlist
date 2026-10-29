require "test_helper"

class RegistrationFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  test "invitation email registration welcome and subsequent login" do
    inviter = users(:sean)

    confirm_and_sign_in inviter

    assert_no_emails do
      post invitations_path, params: { invitation: { email: "newuser@test.com" } }
    end

    perform_enqueued_jobs(only: InvitationNotificationJob)

    email = ActionMailer::Base.deliveries.last
    link = Nokogiri::HTML(email.html_part.body.decoded).at_css("a")["href"]
    uri = URI.parse(link)

    sign_out inviter

    get "#{uri.path}?#{uri.query}"

    assert_response :success

    token = response.parsed_body.at_css("input[name='token']")["value"]

    assert_no_emails do
      post invitation_acceptance_path, params: { token: token,
        user: { username: "newuser", password: "test123456", password_confirmation: "test123456" } }
    end

    assert_redirected_to friends_path

    user = User.find_by!(email: "newuser@test.com")

    assert user.confirmed?
    assert_includes inviter.friends, user
    assert_enqueued_with job: RegistrationNotificationJob, args: [ user ]
    assert_enqueued_with job: RegistrationWelcomeJob, args: [ user ]

    perform_enqueued_jobs(only: [ RegistrationNotificationJob, RegistrationWelcomeJob ])

    assert ActionMailer::Base.deliveries.any? { |message| message.subject.start_with?("Welcome to ") }
    assert_not ActionMailer::Base.deliveries.any? { |message| message.subject == "Confirmation instructions" }

    delete destroy_user_session_path

    post user_session_path, params: { user: { username: "newuser", password: "test123456" } }

    assert_response :redirect

    follow_redirect!

    assert_response :success
  end
end
