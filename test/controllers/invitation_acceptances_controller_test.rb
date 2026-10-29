require "test_helper"

class InvitationAcceptancesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @invitation = users(:sean).sent_invitations.create!(email: "new@example.com")
  end

  test "anonymous GET is read only and identifies inviter and invited email" do
    assert_no_difference [ "User.count", "Friendship.count", "Invitation.count" ] do
      get invitation_acceptance_path(token: @invitation.acceptance_token)
    end

    assert_response :success
    assert_includes response.body, @invitation.inviter.username
    assert_includes response.body, @invitation.email
    assert_nil @invitation.reload.accepted_at
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "missing malformed altered and wrong purpose tokens fail" do
    token = @invitation.acceptance_token

    [ nil, "invalid", token + "x", @invitation.signed_id(purpose: :other) ].each do |invalid|
      get invitation_acceptance_path(token: invalid)

      assert_response :not_found

      post invitation_acceptance_path, params: { token: invalid }

      assert_response :not_found
    end
  end

  test "tokens do not expire with time" do
    token = @invitation.acceptance_token

    travel 10.years do
      get invitation_acceptance_path(token: token)

      assert_response :success
    end
  end

  test "cancelled and consumed tokens fail and reinviting does not reactivate old link" do
    token = @invitation.acceptance_token
    inviter = @invitation.inviter

    @invitation.destroy!

    replacement = inviter.sent_invitations.create!(email: "new@example.com")

    get invitation_acceptance_path(token: token)

    assert_response :not_found

    replacement.update!(invitee: users(:casie), accepted_at: Time.current)

    get invitation_acceptance_path(token: replacement.acceptance_token)

    assert_response :not_found
  end

  test "new recipient is confirmed and befriended with notifications only in jobs" do
    assert_no_emails do
      assert_difference "User.count", 1 do
        post invitation_acceptance_path, params: signup_params(user: {
          username: "newuser", email: "forged@example.com", confirmed_at: nil,
          password: "test123456", password_confirmation: "test123456"
        })
      end
    end

    assert_redirected_to friends_path

    recipient = User.find_by!(email: @invitation.email)

    assert recipient.confirmed?
    assert_nil recipient.confirmation_token
    assert_equal recipient, @invitation.reload.invitee

    friendship = Friendship.sole

    assert_equal @invitation.inviter_id, friendship.requester_id
    assert_equal recipient.id, friendship.recipient_id
    assert friendship.accepted_at.present?
    assert_enqueued_with job: RegistrationNotificationJob, args: [ recipient ]
    assert_enqueued_with job: RegistrationWelcomeJob, args: [ recipient ]
    assert_no_enqueued_jobs only: [ FriendshipRequestNotificationJob, FriendshipAcceptanceNotificationJob ]

    assert_no_enqueued_jobs do
      post invitation_acceptance_path, params: signup_params

      assert_response :not_found
    end
  end

  test "invalid signup preserves nonsecret values without consuming invitation" do
    assert_no_enqueued_jobs do
      assert_no_difference [ "User.count", "Friendship.count" ] do
        post invitation_acceptance_path, params: signup_params(user: {
          username: "newuser", password: "short", password_confirmation: "different"
        })
      end
    end

    assert_response :unprocessable_entity
    assert_select "input[name='user[username]'][value='newuser']"
    assert_select "input[type='password'][value]", count: 0
    assert_nil @invitation.reload.accepted_at
  end

  test "confirmed recipient must sign in and acceptance preserves other invitations" do
    recipient = users(:casie)

    recipient.confirm

    @invitation.update!(email: recipient.email)

    other = users(:amelia).sent_invitations.create!(email: recipient.email)

    assert_no_difference "Friendship.count" do
      post invitation_acceptance_path, params: { token: @invitation.acceptance_token }
    end

    assert_response :unprocessable_entity
    assert_nil @invitation.reload.accepted_at

    confirm_and_sign_in recipient

    assert_no_enqueued_jobs do
      post invitation_acceptance_path, params: { token: @invitation.acceptance_token }
    end

    assert_redirected_to friends_path
    assert_nil other.reload.accepted_at
    assert_equal recipient, @invitation.reload.invitee
  end

  test "wrong signed in account cannot accept and can switch and return through login" do
    recipient = users(:casie)

    recipient.confirm

    @invitation.update!(email: recipient.email)

    confirm_and_sign_in users(:amelia)

    get invitation_acceptance_path(token: @invitation.acceptance_token)

    assert_select "button", text: "Switch accounts"

    assert_no_difference "Friendship.count" do
      post invitation_acceptance_path, params: { token: @invitation.acceptance_token }
    end

    assert_response :unprocessable_entity
    assert_nil @invitation.reload.accepted_at

    post switch_invitation_account_path, params: { token: @invitation.acceptance_token, return_to: "https://example.org" }

    assert_redirected_to new_user_session_path

    post user_session_path, params: { user: { username: recipient.username, password: "test123456" } }

    assert_redirected_to invitation_acceptance_path(token: @invitation.acceptance_token)
    assert_nil @invitation.reload.accepted_at
  end

  test "unconfirmed account needs credentials and invitation confirmation preserves pending email change" do
    recipient = users(:casie)

    recipient.update_columns(unconfirmed_email: "changed@example.com")

    @invitation.update!(email: recipient.email)

    assert_no_emails do
      post invitation_acceptance_path, params: { token: @invitation.acceptance_token, user: { password: "wrong" } }
    end

    assert_response :unprocessable_entity
    assert_not recipient.reload.confirmed?
    assert_equal 1, recipient.failed_attempts
    assert_nil @invitation.reload.accepted_at

    assert_no_enqueued_jobs do
      post invitation_acceptance_path, params: { token: @invitation.acceptance_token, user: { password: "test123456" } }
    end

    assert_redirected_to friends_path
    assert recipient.reload.confirmed?
    assert_equal @invitation.email, recipient.email
    assert_equal "changed@example.com", recipient.unconfirmed_email
    assert_equal 0, recipient.failed_attempts
  end

  test "lockout cannot be bypassed and unlock email is sent through a job" do
    recipient = users(:casie)

    @invitation.update!(email: recipient.email)

    recipient.update_columns(failed_attempts: User.maximum_attempts - 1)

    assert_no_difference "ActionMailer::Base.deliveries.size" do
      assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
        post invitation_acceptance_path, params: { token: @invitation.acceptance_token, user: { password: "wrong" } }
      end
    end

    assert_response :unprocessable_entity
    assert recipient.reload.access_locked?

    post invitation_acceptance_path, params: { token: @invitation.acceptance_token, user: { password: "test123456" } }

    assert_response :unprocessable_entity
    assert_not recipient.reload.confirmed?
    assert_nil @invitation.reload.accepted_at
  end

  [ true, false ].each do |reverse|
    test "acceptance preserves existing pending pair direction reverse #{reverse}" do
      recipient = users(:casie)

      recipient.confirm

      @invitation.update!(email: recipient.email)

      requester = @invitation.inviter

      if reverse
        friendship = Friendship.create!(requester: recipient, recipient: requester)
      else
        friendship = Friendship.create!(requester: requester, recipient: recipient)
      end

      original_requester_id = friendship.requester_id

      confirm_and_sign_in recipient

      assert_no_difference "Friendship.count" do
        post invitation_acceptance_path, params: { token: @invitation.acceptance_token }
      end

      assert_redirected_to friends_path
      assert friendship.reload.accepted_at.present?
      assert_equal original_requester_id, friendship.requester_id
    end
  end

  test "acceptance preserves an already accepted friendship" do
    recipient = users(:casie)

    recipient.confirm

    @invitation.update!(email: recipient.email)

    friendship = Friendship.create!(requester: recipient, recipient: @invitation.inviter, accepted_at: 1.day.ago)

    accepted_at = friendship.accepted_at

    confirm_and_sign_in recipient

    post invitation_acceptance_path, params: { token: @invitation.acceptance_token }

    assert_redirected_to friends_path
    assert_equal accepted_at, friendship.reload.accepted_at
  end

  test "pending changed email never grants authority over the existing account" do
    recipient = users(:casie)

    recipient.confirm

    recipient.update_columns(unconfirmed_email: @invitation.email)

    confirm_and_sign_in recipient

    post invitation_acceptance_path, params: { token: @invitation.acceptance_token }

    assert_response :unprocessable_entity
    assert_nil @invitation.reload.accepted_at
  end

  test "cancelled token cannot register and invitation is rechecked after waiting for lock" do
    changed = false
    subscriber = lambda do |*, payload|
      if !changed && payload[:sql].start_with?("SELECT") && payload[:sql].include?('"users"')
        changed = true

        @invitation.destroy!
      end
    end

    assert_no_difference "User.count" do
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        post invitation_acceptance_path, params: signup_params
      end
    end

    assert changed
    assert_response :not_found
  end

  test "failure saving acceptance rolls back account friendship and notifications" do
    reject_acceptance = ->(invitation) { throw :abort if invitation.accepted_at.present? }

    Invitation.set_callback(:validation, :before, reject_acceptance)

    begin
      assert_no_enqueued_jobs do
        assert_no_difference [ "User.count", "Friendship.count" ] do
          post invitation_acceptance_path, params: signup_params
        end
      end

      assert_response :unprocessable_entity
      assert_nil @invitation.reload.accepted_at
    ensure
      Invitation.skip_callback(:validation, :before, reject_acceptance)
    end
  end

  test "registration notifications wait for commit" do
    assert_enqueued_jobs 2 do
      Invitation.transaction do
        assert_no_enqueued_jobs do
          post invitation_acceptance_path, params: signup_params
        end
      end
    end
  end

  test "email changed while waiting cannot accept for the old address" do
    recipient = users(:casie)

    recipient.confirm

    @invitation.update!(email: recipient.email)

    confirm_and_sign_in recipient

    changed = false
    subscriber = lambda do |*, payload|
      if !changed && payload[:sql].start_with?("SELECT") && payload[:sql].include?('"users"')
        changed = true

        recipient.update_columns(email: "changed@example.com")
      end
    end

    assert_no_difference "Friendship.count" do
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        post invitation_acceptance_path, params: { token: @invitation.acceptance_token }
      end
    end

    assert changed
    assert_response :unprocessable_entity
    assert_nil @invitation.reload.accepted_at
  end

  test "a competing reverse friendship is accepted without duplicate notifications" do
    recipient = users(:casie)

    recipient.confirm

    @invitation.update!(email: recipient.email)

    confirm_and_sign_in recipient

    inserted = false
    subscriber = lambda do |*, payload|
      if !inserted && payload[:sql].start_with?("SELECT") && payload[:sql].include?('"friendships"')
        inserted = true

        Friendship.insert_all!([ { requester_id: recipient.id, recipient_id: @invitation.inviter_id } ])
      end
    end
    inviter_id = @invitation.inviter_id
    conflict = lambda do |friendship|
      if friendship.new_record? && friendship.requester_id == inviter_id
        raise ActiveRecord::RecordNotUnique
      end
    end

    Friendship.set_callback(:validation, :before, conflict)

    begin
      assert_no_enqueued_jobs do
        ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
          post invitation_acceptance_path, params: { token: @invitation.acceptance_token }
        end
      end

      assert inserted
      assert_redirected_to friends_path
      assert_equal recipient.id, Friendship.sole.requester_id
      assert Friendship.sole.accepted_at.present?
    ensure
      Friendship.skip_callback(:validation, :before, conflict)
    end
  end

  test "outer rollback undoes acceptance and new account without notifications" do
    assert_no_enqueued_jobs do
      assert_no_difference [ "User.count", "Friendship.count" ] do
        Invitation.transaction do
          post invitation_acceptance_path, params: signup_params

          raise ActiveRecord::Rollback
        end
      end
    end

    assert_nil @invitation.reload.accepted_at
  end

  test "account created after initial lookup requires authentication instead of overwriting" do
    inserted = false
    subscriber = lambda do |*, payload|
      if !inserted && payload[:sql].start_with?("SELECT") && payload[:sql].include?('"users"')
        inserted = true
        user = User.new(username: "anotheruser", email: @invitation.email, password: "different123")

        user.skip_confirmation!

        user.save!
      end
    end

    assert_no_difference "Friendship.count" do
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        post invitation_acceptance_path, params: signup_params
      end
    end

    assert inserted
    assert_response :unprocessable_entity
    assert_equal "anotheruser", User.find_by!(email: @invitation.email).username
    assert_nil @invitation.reload.accepted_at
  end

  test "cancelled and consumed POST tokens cannot create accounts or recreate removed friendship" do
    token = @invitation.acceptance_token

    @invitation.destroy!

    replacement = users(:sean).sent_invitations.create!(email: "new@example.com")

    assert_no_difference [ "User.count", "Friendship.count" ] do
      post invitation_acceptance_path, params: { token: token, user: signup_params[:user] }
    end

    assert_response :not_found

    post invitation_acceptance_path, params: { token: replacement.acceptance_token, user: signup_params[:user] }

    assert_redirected_to friends_path

    recipient = replacement.reload.invitee
    friendship = Friendship.sole

    delete friendship_path(friendship)

    assert_redirected_to friends_path

    assert_no_enqueued_jobs do
      assert_no_difference [ "User.count", "Friendship.count" ] do
        post invitation_acceptance_path, params: { token: replacement.acceptance_token }
      end
    end

    assert_response :not_found
    assert_not_includes recipient.friends, replacement.inviter
    assert replacement.reload.accepted_at.present?
  end

  test "failed acceptance rolls back confirmation of an existing unconfirmed account" do
    recipient = users(:casie)

    @invitation.update!(email: recipient.email)

    reject_acceptance = ->(invitation) { throw :abort if invitation.accepted_at.present? }

    Invitation.set_callback(:validation, :before, reject_acceptance)

    begin
      assert_no_enqueued_jobs do
        assert_no_difference "Friendship.count" do
          post invitation_acceptance_path, params: { token: @invitation.acceptance_token,
            user: { password: "test123456" } }
        end
      end

      assert_response :unprocessable_entity
      assert_not recipient.reload.confirmed?
      assert_nil @invitation.reload.accepted_at

      get friends_path

      assert_response :not_found
    ensure
      Invitation.skip_callback(:validation, :before, reject_acceptance)
    end
  end

  test "acceptance rechecks consumed state after acquiring invitation lock" do
    recipient = users(:casie)

    recipient.confirm

    @invitation.update!(email: recipient.email)

    confirm_and_sign_in recipient

    changed = false
    subscriber = lambda do |*, payload|
      if !changed && payload[:sql].start_with?("SELECT") && payload[:sql].include?('"users"')
        changed = true

        @invitation.update_columns(invitee_id: recipient.id, accepted_at: Time.current)
      end
    end

    assert_no_enqueued_jobs do
      assert_no_difference [ "User.count", "Friendship.count" ] do
        ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
          post invitation_acceptance_path, params: { token: @invitation.acceptance_token }
        end
      end
    end

    assert changed
    assert_response :not_found
  end

  private

  def signup_params(user: { username: "newuser", password: "test123456", password_confirmation: "test123456" })
    { token: @invitation.acceptance_token, user: user }
  end
end
