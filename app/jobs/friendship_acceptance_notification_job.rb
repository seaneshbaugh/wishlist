class FriendshipAcceptanceNotificationJob < ApplicationJob
  queue_as :friendship_notification

  def perform(friendship_id)
    friendship = Friendship.accepted.includes(:requester, :recipient).find_by(id: friendship_id)

    return unless friendship

    FriendshipMailer.acceptance_message(friendship).deliver_now
  end
end
