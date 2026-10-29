class InvitationAcceptancesController < ApplicationController
  before_action :set_policy_headers

  def show
    load_invitation
    load_recipient

    store_location_for(:user, invitation_acceptance_path(token: params[:token]))
  end

  def create
    load_invitation

    accepted = false
    new_account = false

    begin
      Invitation.transaction do
        recipient = User.find_by(email: @invitation.email)

        # Always lock users in ID order before the invitation and friendship.
        User.where(id: [ @invitation.inviter_id, recipient&.id, current_user&.id ].compact)
          .order(:id).lock.load

        @invitation.lock!

        raise ActiveRecord::RecordNotFound if @invitation.accepted_at.present?

        load_recipient

        if !current_user && @user.persisted? && @user.id != recipient&.id
          # This account appeared after we chose which user rows to lock.
          # Ask for a fresh submission rather than checking credentials on an unlocked row.
          @form_error = t(".account_changed")
        elsif current_user
          @user = User.find(current_user.id)

          if @user.email != @invitation.email
            @form_error = t(".wrong_account")
          elsif !@user.active_for_authentication?
            @form_error = t(".inactive")
          end
        elsif @user.persisted?
          if @user.confirmed?
            @form_error = t(".sign_in_required")
          elsif @user.valid_for_authentication? { @user.valid_password?(params.dig(:user, :password).to_s) }
            @user.skip_confirmation!

            if @user.active_for_authentication?
              @user.save!
              @user.after_database_authentication
            else
              @form_error = t(".inactive")
            end
          else
            @form_error = t(".invalid_credentials")
          end
        else
          @user.assign_attributes(params.require(:user).permit(:username, :password, :password_confirmation))
          @user.skip_confirmation!
          @user.save!

          new_account = true
        end

        unless @form_error
          @invitation.accept!(@user)

          accepted = true
        end
      end
    rescue ActiveRecord::RecordInvalid => error
      if error.record.is_a?(User)
        @user = error.record
      else
        @form_error = t(".error")
      end
    rescue ActiveRecord::RecordNotUnique
      # A different invitation may have created this email's account while we
      # were saving. Never overwrite that account or authenticate it with a token.
      recipient = User.find_by(email: @invitation.email)

      if recipient
        @user = recipient
        @form_error = t(".sign_in_required")
      elsif @user&.new_record?
        # A competing signup may instead have taken the submitted username.
        raise if @user.valid?
      else
        raise
      end
    end

    if accepted
      if new_account
        ActiveRecord.after_all_transactions_commit do
          RegistrationNotificationJob.perform_later(@user)
          RegistrationWelcomeJob.perform_later(@user)
        end
      end

      sign_in(:user, @user)

      stored_location_for(:user)

      flash[:success] = t(".success")

      redirect_to friends_url, status: :see_other
    else
      store_location_for(:user, invitation_acceptance_path(token: params[:token]))

      @user.password = @user.password_confirmation = nil

      render "show", status: :unprocessable_entity
    end
  end

  def switch_account
    load_invitation

    sign_out(:user)

    store_location_for(:user, invitation_acceptance_path(token: params[:token]))

    redirect_to new_user_session_url, status: :see_other
  end

  private

  def load_invitation
    @invitation = Invitation.find_signed(params[:token], purpose: :invitation)

    raise ActiveRecord::RecordNotFound unless @invitation && @invitation.accepted_at.nil?
  end

  def load_recipient
    @user = User.find_by(email: @invitation.email) || User.new(email: @invitation.email)
  end

  def set_policy_headers
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Cache-Control"] = "no-store"
  end
end
