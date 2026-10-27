class InvitationMailer < ApplicationMailer
  def invitation_message(invitation)
    @invitation = invitation
    @existing_account = User.exists?(email: invitation.email)
    @acceptance_url = invitation_acceptance_url(token: invitation.acceptance_token)

    mail to: invitation.email, subject: t(".subject", username: invitation.inviter.username)
  end
end
