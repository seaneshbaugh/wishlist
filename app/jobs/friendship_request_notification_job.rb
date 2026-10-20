class FriendshipRequestNotificationJob < ApplicationJob
  queue_as :friendship_notification

  def perform(friendship_id)
    friendship = Friendship.pending.includes(:requester, :recipient).find_by(id: friendship_id)

    return unless friendship

    FriendshipMailer.request_message(friendship).deliver_now
  end
end
