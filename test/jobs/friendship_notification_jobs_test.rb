require "test_helper"

class FriendshipNotificationJobsTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  class FailingDelivery
    def initialize(*)
    end

    def deliver!(_mail)
      raise IOError, "SMTP unavailable"
    end
  end

  setup do
    @requester = users(:sean)
    @recipient = users(:casie)
    @friendship = Friendship.create!(requester: @requester, recipient: @recipient)
  end

  test "request job sends to the recipient only while pending" do
    assert_emails 1 do
      FriendshipRequestNotificationJob.perform_now(@friendship.id)
    end

    assert_equal [ @recipient.email ], ActionMailer::Base.deliveries.last.to

    @friendship.update!(accepted_at: Time.current)

    assert_no_emails do
      FriendshipRequestNotificationJob.perform_now(@friendship.id)
    end
  end

  test "acceptance job sends to the requester only after acceptance" do
    assert_no_emails do
      FriendshipAcceptanceNotificationJob.perform_now(@friendship.id)
    end

    @friendship.update!(accepted_at: Time.current)

    assert_emails 1 do
      FriendshipAcceptanceNotificationJob.perform_now(@friendship.id)
    end

    assert_equal [ @requester.email ], ActionMailer::Base.deliveries.last.to
  end

  test "notification jobs ignore deleted friendships and never notify a replacement" do
    old_id = @friendship.id

    @friendship.destroy!

    Friendship.create!(requester: @recipient, recipient: @requester)

    assert_no_emails do
      FriendshipRequestNotificationJob.perform_now(old_id)
      FriendshipAcceptanceNotificationJob.perform_now(old_id)
    end
  end

  %i[requester recipient].each do |participant|
    test "notification jobs tolerate deletion of #{participant}" do
      instance_variable_get("@#{participant}").destroy!

      assert_no_emails do
        FriendshipRequestNotificationJob.perform_now(@friendship.id)
        FriendshipAcceptanceNotificationJob.perform_now(@friendship.id)
      end
    end
  end

  test "jobs use the current email instead of an outdated queued address" do
    @recipient.update_columns(email: "changed@example.com")

    FriendshipRequestNotificationJob.perform_now(@friendship.id)

    assert_equal [ "changed@example.com" ], ActionMailer::Base.deliveries.last.to
  end

  test "delivery failures do not roll back the saved request or acceptance" do
    original_method = ActionMailer::Base.delivery_method
    original_raise = ActionMailer::Base.raise_delivery_errors

    ActionMailer::Base.add_delivery_method :friendship_failure, FailingDelivery
    ActionMailer::Base.delivery_method = :friendship_failure
    ActionMailer::Base.raise_delivery_errors = true

    assert_raises IOError do
      FriendshipRequestNotificationJob.perform_now(@friendship.id)
    end

    assert @friendship.reload.persisted?
    assert_nil @friendship.accepted_at

    @friendship.update!(accepted_at: Time.current)

    assert_raises IOError do
      FriendshipAcceptanceNotificationJob.perform_now(@friendship.id)
    end

    assert @friendship.reload.accepted_at.present?
  ensure
    ActionMailer::Base.delivery_method = original_method
    ActionMailer::Base.raise_delivery_errors = original_raise
  end
end
