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

      respond_to do |format|
        format.turbo_stream do
          load_invitations

          render "create", locals: { message: message }
        end
        format.html do
          flash[:success] = message

          redirect_to invitations_url, status: :see_other
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render "form_error", status: :unprocessable_entity
        end
        format.html do
          load_invitations

          render "index", status: :unprocessable_entity
        end
      end
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

    respond_to do |format|
      format.turbo_stream do
        render "resend", locals: { message: t(".success") }
      end
      format.html do
        flash[:success] = t(".success")

        redirect_to invitations_url, status: :see_other
      end
    end
  end

  def destroy
    invitation = current_user.sent_invitations.find(params[:id])

    destroyed = invitation.with_lock do
      raise ActiveRecord::RecordNotFound if invitation.accepted_at.present?

      invitation.destroy
    end

    respond_to do |format|
      format.turbo_stream do
        if destroyed
          load_invitations

          render "destroy", locals: { message: t(".success") }
        else
          render "destroy_error", locals: { message: t(".error") }, status: :unprocessable_entity
        end
      end
      format.html do
        if destroyed
          flash[:success] = t(".success")
        else
          flash[:error] = t(".error")
        end

        redirect_to invitations_url, status: :see_other
      end
    end
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
