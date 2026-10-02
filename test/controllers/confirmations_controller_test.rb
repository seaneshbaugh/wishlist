require "test_helper"

class ConfirmationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = User.create!(username: "newuser", email: "newuser@test.com", password: "test123456", password_confirmation: "test123456")
  end

  test "successful confirmation enqueues welcome job" do
    token = @user.confirmation_token

    assert_enqueued_with(job: RegistrationWelcomeJob) do
      get user_confirmation_path, params: { confirmation_token: token }
    end
  end

  test "invalid confirmation token does not enqueue welcome job" do
    assert_no_enqueued_jobs(only: RegistrationWelcomeJob) do
      get user_confirmation_path, params: { confirmation_token: "not-a-real-token" }
    end
  end

  test "confirming an already confirmed user does not enqueue another welcome job" do
    raw_token = @user.send_confirmation_instructions

    get user_confirmation_path, params: { confirmation_token: raw_token }

    clear_enqueued_jobs

    get user_confirmation_path, params: { confirmation_token: raw_token }

    assert_no_enqueued_jobs only: RegistrationWelcomeJob
  end
end
