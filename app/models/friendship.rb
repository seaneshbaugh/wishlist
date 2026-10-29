class Friendship < ApplicationRecord
  scope :pending, -> { where(accepted_at: nil) }
  scope :accepted, -> { where.not(accepted_at: nil) }

  belongs_to :requester, class_name: "User", inverse_of: :outgoing_friendships
  belongs_to :recipient, class_name: "User", inverse_of: :incoming_friendships

  validate :participants_are_different
  validate :user_pair_is_unique

  def self.between(first_user, second_user)
    where(requester: first_user, recipient: second_user)
      .or(where(requester: second_user, recipient: first_user)).first
  end

  private

  def participants_are_different
    if requester_id && requester_id == recipient_id
      errors.add(:recipient, :same_as_requester)
    end
  end

  def user_pair_is_unique
    return unless requester_id && recipient_id

    existing = Friendship.where(requester_id: requester_id, recipient_id: recipient_id)
      .or(Friendship.where(requester_id: recipient_id, recipient_id: requester_id))
      .where.not(id: id)

    errors.add(:base, :already_exists) if existing.exists?
  end
end
