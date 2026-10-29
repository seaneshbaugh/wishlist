require "test_helper"

class InvitationNotificationJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @invitation = users(:sean).sent_invitations.create!(email: "new@example.com")
  end

  test "job sends multipart email with consent and a purpose scoped token" do
    assert_emails 1 do
      InvitationNotificationJob.perform_now(@invitation.id)
    end

    email = ActionMailer::Base.deliveries.last

    assert_equal [ @invitation.email ], email.to
    assert email.multipart?

    [ email.html_part, email.text_part ].each do |part|
      assert_includes part.body.decoded, "Create an account"
      assert_includes part.body.decoded, "Accepting establishes friendship"
      assert_includes part.body.decoded, "remove the friendship afterward"
      assert_includes part.body.decoded, @invitation.inviter.username
      assert_includes part.body.decoded, @invitation.acceptance_token
    end
  end

  test "wording reflects existing account at execution time" do
    user = User.new(username: "newuser", email: @invitation.email, password: "test123456")

    user.skip_confirmation!
    user.save!

    InvitationNotificationJob.perform_now(@invitation.id)

    email = ActionMailer::Base.deliveries.last

    assert_includes email.text_part.body.decoded, "already have an account"
    assert_includes email.text_part.body.decoded, "friend request"
    assert_not_includes email.text_part.body.decoded, "Create an account"
  end

  test "cancelled and accepted invitations are skipped" do
    @invitation.destroy!

    assert_no_emails { InvitationNotificationJob.perform_now(@invitation.id) }

    accepted = users(:sean).sent_invitations.create!(email: users(:casie).email,
      invitee: users(:casie), accepted_at: Time.current)

    assert_no_emails { InvitationNotificationJob.perform_now(accepted.id) }
  end

  test "mail delivery failure does not cancel or accept the saved invitation" do
    interceptor = Class.new do
      def self.delivering_email(_message)
        raise IOError, "Mail delivery unavailable"
      end
    end

    ActionMailer::Base.register_interceptor(interceptor)

    begin
      assert_raises IOError do
        InvitationNotificationJob.perform_now(@invitation.id)
      end

      assert_nil @invitation.reload.accepted_at
      assert_nil @invitation.invitee_id
      assert_equal @invitation, Invitation.find_signed(@invitation.acceptance_token, purpose: :invitation)
    ensure
      ActionMailer::Base.unregister_interceptor(interceptor)
    end
  end
end
