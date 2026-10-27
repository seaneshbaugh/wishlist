class InvitationNotificationJob < ApplicationJob
  queue_as :invitation_notification

  def perform(invitation_id)
    invitation = Invitation.pending.includes(:inviter).find_by(id: invitation_id)

    return unless invitation

    InvitationMailer.invitation_message(invitation).deliver_now
  end
end
