class InvitationsController < ApplicationController
  before_action :authenticate_user!

  def index
    @invitation = current_user.sent_invitations.build

    load_invitations
  end

  def create
    @invitation = current_user.sent_invitations.build(params.require(:invitation).permit(:email))

    begin
      @invitation = find_or_create_invitation(@invitation)
      valid = @invitation.valid?
    rescue ActiveRecord::RecordInvalid => error
      @invitation = error.record
      valid = false
    end

    if valid
      if @invitation.previously_new_record?
        ActiveRecord.after_all_transactions_commit do
          InvitationNotificationJob.perform_later(@invitation.id)
        end

        message = t(".success")
      else
        message = t(".already_pending")
      end

      flash[:success] = message

      redirect_to invitations_url, status: :see_other
    else
      load_invitations

      render "index", status: :unprocessable_entity
    end
  end

  def resend
    invitation = current_user.sent_invitations.find(params[:id])

    invitation.with_lock do
      raise ActiveRecord::RecordNotFound if invitation.accepted_at.present?

      ActiveRecord.after_all_transactions_commit do
        InvitationNotificationJob.perform_later(invitation.id)
      end
    end

    flash[:success] = t(".success")

    redirect_to invitations_url, status: :see_other
  end

  def destroy
    invitation = current_user.sent_invitations.find(params[:id])

    destroyed = invitation.with_lock do
      raise ActiveRecord::RecordNotFound if invitation.accepted_at.present?

      invitation.destroy
    end

    if destroyed
      flash[:success] = t(".success")
    else
      flash[:error] = t(".error")
    end

    redirect_to invitations_url, status: :see_other
  end

  private

  def find_or_create_invitation(invitation)
    current_user.sent_invitations.pending.find_by(email: invitation.email) ||
      Invitation.transaction(requires_new: true) { invitation.tap(&:save!) }
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Another request may have inserted the same pending invitation after lookup.
    current_user.sent_invitations.pending.find_by(email: invitation.email) || raise
  end

  def load_invitations
    @invitations = current_user.sent_invitations.order(created_at: :desc, id: :desc)
  end
end
