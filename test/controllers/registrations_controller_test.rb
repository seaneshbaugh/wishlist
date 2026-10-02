require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "successful registration enqueues registration notification for created user" do
    perform_enqueued_jobs do
      post user_registration_path, params: { user: { username: "newuser", email: "newuser@test.com", password: "test123456", password_confirmation: "test123456" } }
    end

    user = User.find_by!(email: "newuser@test.com")

    assert_performed_with(job: RegistrationNotificationJob, args: [user])
  end

  test "invalid registration does not enqueue reigstration notification" do
    assert_no_enqueued_jobs(only: RegistrationNotificationJob) do
      post user_registration_path, params: { user: { username: "", email: "invalid", password: "short", password_confirmation: "different" } }
    end
  end
end
