class FriendshipsController < ApplicationController
  before_action :authenticate_user!

  def requests
    load_requests
  end

  def create
    @email = params.require(:friendship).permit(:email)[:email].to_s.strip.downcase

    if Devise.email_regexp.match?(@email)
      recipient = User.where.not(confirmed_at: nil).find_by(email: @email)
      @form_error = t(".self_request") if recipient == current_user
    else
      @form_error = t(".invalid_email")
    end

    if @form_error
      respond_to do |format|
        format.turbo_stream do
          render "form_error", status: :unprocessable_entity
        end
        format.html do
          load_requests

          flash.now[:error] = @form_error

          render "requests", status: :unprocessable_entity
        end
      end

      return
    end

    friendship = find_or_request_friendship(recipient) if recipient

    if friendship&.previously_new_record?
      ActiveRecord.after_all_transactions_commit do
        FriendshipRequestNotificationJob.perform_later(friendship.id)
      end
    end

    if friendship&.accepted_at.present?
      respond_to do |format|
        format.turbo_stream do
          render "create", locals: { message: t(".already_friends") }
        end
        format.html do
          flash[:notice] = t(".already_friends")

          redirect_to friends_url, status: :see_other
        end
      end
    elsif friendship && friendship.recipient_id == current_user.id
      flash[:notice] = t(".incoming_request", username: recipient.username)

      redirect_to requests_friendships_url, status: :see_other
    else
      respond_to do |format|
        format.turbo_stream do
          render "create", locals: { message: t(".success") }
        end
        format.html do
          flash[:success] = t(".success")

          redirect_to friends_url, status: :see_other
        end
      end
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

    respond_to do |format|
      format.turbo_stream do
        load_friends
        load_requests

        render "update", locals: { message: t(".success") }
      end
      format.html do
        flash[:success] = t(".success")

        redirect_to friends_url, status: :see_other
      end
    end
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

    respond_to do |format|
      format.turbo_stream do
        if destroyed
          load_friends
          load_requests

          render "update", locals: { message: t(".success") }
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

        if accepted
          redirect_to friends_url, status: :see_other
        else
          redirect_to requests_friendships_url, status: :see_other
        end
      end
    end
  end

  private

  def load_friends
    @friends = current_user.friends.alphabetical.load
    @visible_list_counts = List.publicly_visible.where(user_id: @friends.map(&:id)).group(:user_id).count
    @friendships_by_friend_id = Friendship.accepted
      .where(requester: current_user).or(Friendship.accepted.where(recipient: current_user))
      .index_by do |friendship|
        if friendship.requester_id == current_user.id
          friendship.recipient_id
        else
          friendship.requester_id
        end
      end
  end

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
