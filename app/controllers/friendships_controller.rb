class FriendshipsController < ApplicationController
  before_action :authenticate_user!

  def requests
    load_requests
  end

  def create
    @email = params.require(:friendship).permit(:email)[:email].to_s.strip.downcase

    unless Devise.email_regexp.match?(@email)
      load_requests

      flash.now[:error] = t(".invalid_email")

      return render "requests", status: :unprocessable_entity
    end

    recipient = User.where.not(confirmed_at: nil).find_by(email: @email)

    if recipient == current_user
      load_requests

      flash.now[:error] = t(".self_request")

      return render "requests", status: :unprocessable_entity
    end

    friendship = find_or_request_friendship(recipient) if recipient

    if friendship&.previously_new_record?
      ActiveRecord.after_all_transactions_commit do
        FriendshipRequestNotificationJob.perform_later(friendship.id)
      end
    end

    if friendship&.accepted_at.present?
      flash[:notice] = t(".already_friends")

      redirect_to friends_url, status: :see_other
    elsif friendship && friendship.recipient_id == current_user.id
      flash[:notice] = t(".incoming_request", username: recipient.username)

      redirect_to requests_friendships_url, status: :see_other
    else
      flash[:success] = t(".success")

      redirect_to friends_url, status: :see_other
    end
  end

  def accept
    friendship = current_user.incoming_friendships.find(params[:id])

    friendship.with_lock do
      raise ActiveRecord::RecordNotFound if friendship.accepted_at.present?

      friendship.update!(accepted_at: Time.current)
    end

    ActiveRecord.after_all_transactions_commit do
      FriendshipAcceptanceNotificationJob.perform_later(friendship.id)
    end

    flash[:success] = t(".success")

    redirect_to friends_url, status: :see_other
  end

  def destroy
    friendship = Friendship.where(requester: current_user)
      .or(Friendship.where(recipient: current_user)).find(params[:id])
    accepted = false

    destroyed = friendship.with_lock do
      accepted = friendship.accepted_at.present?

      raise ActiveRecord::RecordNotFound unless accepted || friendship.recipient_id == current_user.id

      friendship.destroy
    end

    if destroyed
      flash[:success] = t(".success")
    else
      flash[:error] = t(".error")
    end

    if accepted
      redirect_to friends_url, status: :see_other
    else
      redirect_to requests_friendships_url, status: :see_other
    end
  end

  private

  def load_requests
    @incoming_requests = current_user.incoming_friendships.pending.includes(:requester).order(:created_at)
  end

  def friendship_between(recipient)
    Friendship.where(requester: current_user, recipient: recipient)
      .or(Friendship.where(requester: recipient, recipient: current_user)).first
  end

  def find_or_request_friendship(recipient)
    friendship_between(recipient) || Friendship.transaction(requires_new: true) do
      current_user.outgoing_friendships.create!(recipient: recipient)
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Another request may have created the pair in either direction after lookup.
    friendship_between(recipient) || raise
  end
end
