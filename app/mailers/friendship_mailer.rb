class FriendshipMailer < ApplicationMailer
  def request_message(friendship)
    @requester = friendship.requester
    @recipient = friendship.recipient

    mail to: @recipient.email, subject: t(".subject", username: @requester.username)
  end

  def acceptance_message(friendship)
    @requester = friendship.requester
    @recipient = friendship.recipient

    mail to: @requester.email, subject: t(".subject", username: @recipient.username)
  end
end
