require "test_helper"

class InvitationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @inviter = users(:sean)
    @recipient = users(:casie)
    @other = users(:amelia)
    confirm_and_sign_in @inviter
  end

  test "creation normalizes email and ignores submitted ownership and acceptance" do
    assert_no_emails do
      assert_enqueued_jobs 1, only: InvitationNotificationJob do
        post invitations_path, params: { invitation: {
          email: " #{@recipient.email.upcase} ", inviter_id: @other.id,
          invitee_id: @recipient.id, accepted_at: Time.current
        } }
      end
    end

    assert_redirected_to invitations_path

    invitation = Invitation.sole

    assert_equal @inviter.id, invitation.inviter_id
    assert_equal @recipient.email, invitation.email
    assert_nil invitation.invitee_id
    assert_nil invitation.accepted_at
    assert_enqueued_with job: InvitationNotificationJob, args: [ invitation.id ]
  end

  test "known and unknown emails produce the same feedback and private listings" do
    [ @recipient.email, "new@example.com" ].each do |email|
      post invitations_path, params: { invitation: { email: email } }

      assert_redirected_to invitations_path
      assert_equal I18n.t("invitations.create.success"), flash[:success]
    end

    foreign = @other.sent_invitations.create!(email: "private@example.com")

    get invitations_path

    assert_response :success
    assert_select "li span", text: @recipient.email
    assert_select "li span", text: "new@example.com"
    assert_select "#invitation_#{foreign.id}", count: 0
    assert_select "a[href*='/friends/']", count: 0
    assert_not_includes response.body, Invitation.first.acceptance_token
    assert_select "li span", text: @recipient.username, count: 0
  end

  test "duplicate create reuses pending invitation without resending" do
    invitation = create_invitation

    assert_no_difference "Invitation.count" do
      assert_no_enqueued_jobs do
        post invitations_path, params: { invitation: { email: " #{invitation.email.upcase} " } }
      end
    end

    assert_redirected_to invitations_path
    assert_equal I18n.t("invitations.create.already_pending"), flash[:success]
  end

  test "invalid self and already friend invitations do not create or send" do
    Friendship.create!(requester: @inviter, recipient: @recipient, accepted_at: Time.current)

    [ "invalid", "", @inviter.email, @recipient.email ].each do |email|
      assert_no_enqueued_jobs do
        assert_no_difference "Invitation.count" do
          post invitations_path, params: { invitation: { email: email } }
        end
      end

      assert_response :unprocessable_entity
      assert_select "[role='alert']"
    end

    assert_includes response.body, "already your friend"
  end

  test "resend queues a job without changing invitation or token" do
    invitation = create_invitation
    token = invitation.acceptance_token
    updated_at = invitation.updated_at

    assert_enqueued_with job: InvitationNotificationJob, args: [ invitation.id ] do
      post resend_invitation_path(invitation), params: { invitation: { email: "changed@example.com" } }
    end

    assert_redirected_to invitations_path
    assert_equal token, invitation.reload.acceptance_token
    assert_equal updated_at, invitation.updated_at
    assert_equal "new@example.com", invitation.email
  end

  test "duplicate creation validates an invitation whose recipient has since become a friend" do
    invitation = @inviter.sent_invitations.create!(email: @recipient.email)
    Friendship.create!(requester: @recipient, recipient: @inviter, accepted_at: Time.current)

    assert_no_enqueued_jobs do
      assert_no_difference "Invitation.count" do
        post invitations_path, params: { invitation: { email: invitation.email } }
      end
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "already your friend"
    assert_select "form[action='#{invitations_path}'][method='post']", count: 1
    assert_select "input[name='_method'][value='patch']", count: 0
  end

  test "cancellation deletes only the pending invitation" do
    invitation = create_invitation

    assert_no_difference "User.count" do
      assert_no_difference "Friendship.count" do
        assert_difference "Invitation.count", -1 do
          delete invitation_path(invitation)
        end
      end
    end

    assert_redirected_to invitations_path
  end

  test "another user cannot resend or cancel and guessed IDs fail" do
    invitation = @other.sent_invitations.create!(email: "new@example.com")

    [ invitation.id, Invitation.maximum(:id) + 1 ].each do |id|
      confirm_and_sign_in @inviter

      assert_no_enqueued_jobs do
        post resend_invitation_path(id)
      end

      assert_response :not_found

      confirm_and_sign_in @inviter

      assert_no_difference "Invitation.count" do
        delete invitation_path(id)
      end

      assert_response :not_found
    end
  end

  test "accepted invitations cannot be resent or cancelled" do
    invitation = create_invitation(invitee: @recipient, accepted_at: Time.current)

    assert_no_enqueued_jobs do
      post resend_invitation_path(invitation)
    end

    assert_response :not_found

    confirm_and_sign_in @inviter

    assert_no_difference "Invitation.count" do
      delete invitation_path(invitation)
    end

    assert_response :not_found
  end

  %i[resend destroy].each do |action|
    test "#{action} rechecks acceptance after acquiring the lock" do
      invitation = create_invitation
      changed = false
      subscriber = lambda do |*, payload|
        if !changed && payload[:sql].start_with?("SELECT") && payload[:sql].include?('"invitations"')
          changed = true
          invitation.update_columns(invitee_id: @recipient.id, accepted_at: Time.current)
        end
      end

      assert_no_enqueued_jobs do
        ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
          if action == :resend
            post resend_invitation_path(invitation)
          else
            delete invitation_path(invitation)
          end
        end
      end

      assert changed
      assert_response :not_found
      assert Invitation.exists?(invitation.id)
      assert invitation.reload.accepted_at.present?
    end
  end

  test "anonymous requests cannot list create resend or cancel" do
    invitation = create_invitation

    sign_out @inviter

    get invitations_path

    assert_response :not_found

    assert_no_enqueued_jobs do
      post invitations_path, params: { invitation: { email: "new@example.com" } }

      assert_response :not_found

      post resend_invitation_path(invitation)

      assert_response :not_found

      delete invitation_path(invitation)

      assert_response :not_found
    end

    assert Invitation.exists?(invitation.id)
  end

  test "creation notification waits for commit and rollback does not enqueue" do
    assert_enqueued_jobs 1, only: InvitationNotificationJob do
      Invitation.transaction do
        assert_no_enqueued_jobs do
          post invitations_path, params: { invitation: { email: "new@example.com" } }
        end
      end
    end

    assert_no_enqueued_jobs do
      Invitation.transaction do
        post invitations_path, params: { invitation: { email: "rolledback@example.com" } }
        raise ActiveRecord::Rollback
      end
    end

    assert_not Invitation.exists?(email: "rolledback@example.com")
  end

  test "resend notification waits for commit and rollback does not enqueue" do
    invitation = create_invitation

    assert_enqueued_jobs 1, only: InvitationNotificationJob do
      Invitation.transaction do
        assert_no_enqueued_jobs { post resend_invitation_path(invitation) }
      end
    end

    assert_no_enqueued_jobs do
      Invitation.transaction do
        post resend_invitation_path(invitation)

        raise ActiveRecord::Rollback
      end
    end
  end

  test "a competing pending insertion is reused without another notification" do
    inserted = false
    subscriber = lambda do |*, payload|
      if !inserted && payload[:sql].start_with?("SELECT") && payload[:sql].include?('"invitations"')
        inserted = true
        create_invitation
      end
    end

    assert_no_enqueued_jobs do
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        post invitations_path, params: { invitation: { email: "new@example.com" } }
      end
    end

    assert inserted
    assert_redirected_to invitations_path
    assert_equal 1, Invitation.count
  end

  test "database uniqueness conflict recovers the competing invitation" do
    inserted = false
    conflict = ->(invitation) { raise ActiveRecord::RecordNotUnique if invitation.new_record? }
    Invitation.set_callback(:validation, :before, conflict)

    begin
      # Insert the competing row without running the callback used to simulate
      # the database conflict in the request's attempted insert.
      subscriber = lambda do |*, payload|
        if !inserted && payload[:sql].start_with?("SELECT") && payload[:sql].include?('"invitations"')
          inserted = true
          Invitation.insert_all!([ { inviter_id: @inviter.id, email: "new@example.com" } ])
        end
      end

      assert_no_enqueued_jobs do
        ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
          post invitations_path, params: { invitation: { email: "new@example.com" } }
        end
      end

      assert inserted
      assert_redirected_to invitations_path
      assert_equal 1, Invitation.count
    ensure
      Invitation.skip_callback(:validation, :before, conflict)
    end
  end

  test "Turbo creation refreshes list and clears form without exposing account identity" do
    post invitations_path, params: { invitation: { email: @recipient.email } }, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action='replace'][target='invitation-form'] input[name='invitation[email]']:not([value])"
    assert_select "turbo-stream[action='replace'][target='invitations'] span", text: @recipient.email
    assert_select "turbo-stream[action='append'][target='flash']", text: /#{Regexp.escape(I18n.t("invitations.create.success"))}/
    assert_nil flash[:success]
    assert_not_includes response.body, Invitation.sole.acceptance_token
    assert_select "a[href*='/friends/']", count: 0

    assert_no_enqueued_jobs do
      post invitations_path, params: { invitation: { email: @recipient.email } }, as: :turbo_stream
    end

    assert_response :success
    assert_select "turbo-stream[target='flash']", text: /already pending/
    assert_equal 1, Invitation.count
  end

  test "Turbo invalid creation replaces only the form and preserves input" do
    post invitations_path, params: { invitation: { email: "invalid" } }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select "turbo-stream[action='replace']", count: 1
    assert_select "turbo-stream[target='invitation-form'] input[value='invalid']"
    assert_select "turbo-stream[target='invitations']", count: 0
    assert_select "turbo-stream[action='append'][target='flash']"
  end

  test "Turbo resend leaves form and list intact and cancellation refreshes the empty list" do
    invitation = create_invitation

    post resend_invitation_path(invitation), as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action='replace']", count: 0
    assert_select "turbo-stream[target='flash']", text: /#{Regexp.escape(I18n.t("invitations.resend.success"))}/

    delete invitation_path(invitation), as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action='replace']", count: 1
    assert_select "turbo-stream[target='invitations']", text: /You haven't sent any invitations/
    assert_select "turbo-stream[target='invitation-form']", count: 0
  end

  test "failed Turbo cancellation leaves the existing DOM in place" do
    invitation = create_invitation
    prevent_destroy = ->(record) { throw :abort if record.id == invitation.id }

    Invitation.set_callback(:destroy, :before, prevent_destroy)

    begin
      assert_no_difference "Invitation.count" do
        delete invitation_path(invitation), as: :turbo_stream
      end

      assert_response :unprocessable_entity
      assert_select "turbo-stream[action='replace']", count: 0
      assert_select "turbo-stream[target='flash']", text: /Unable to cancel/
    ensure
      Invitation.skip_callback(:destroy, :before, prevent_destroy)
    end
  end

  test "accepted history has no mutation controls and navigation requires authentication" do
    invitation = create_invitation(invitee: @recipient, accepted_at: Time.current)

    get invitations_path

    assert_select "nav a[href='#{invitations_path}']", count: 1
    assert_select "#mobile-menu a[href='#{invitations_path}']", count: 1
    assert_select "#invitation_#{invitation.id}", text: /Accepted/
    assert_select "#invitation_#{invitation.id} form", count: 0

    sign_out @inviter

    get new_user_session_path

    assert_select "a[href='#{invitations_path}']", count: 0
  end

  private

  def create_invitation(**attributes)
    @inviter.sent_invitations.create!({ email: "new@example.com" }.merge(attributes))
  end
end
