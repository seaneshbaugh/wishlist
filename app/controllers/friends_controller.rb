class FriendsController < ApplicationController
  before_action :authenticate_user!

  def index
    @friends = current_user.friends.alphabetical.load
    @visible_list_counts = List.publicly_visible.where(user_id: @friends.map(&:id)).group(:user_id).count
    @friendships_by_friend_id = Friendship.accepted
      .where(requester: current_user).or(Friendship.accepted.where(recipient: current_user))
      .index_by { |friendship| friendship.requester_id == current_user.id ? friendship.recipient_id : friendship.requester_id }
  end
end
