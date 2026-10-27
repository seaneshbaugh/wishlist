class Invitation < ApplicationRecord
  scope :pending, -> { where(accepted_at: nil) }
  scope :accepted, -> { where.not(accepted_at: nil) }

  belongs_to :inviter, class_name: "User", inverse_of: :sent_invitations
  belongs_to :invitee, class_name: "User", optional: true, inverse_of: :accepted_invitations

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email,
            presence: true,
            format: { with: Devise.email_regexp, allow_blank: true },
            uniqueness: { scope: :inviter_id, case_sensitive: false,
                          conditions: -> { pending } }, if: -> { accepted_at.nil? }
  validate :acceptance_is_consistent
  validate :participants_are_different
  validate :recipient_is_not_already_a_friend, if: -> { accepted_at.nil? }

  def acceptance_token
    signed_id(purpose: :invitation)
  end

  private

  def recipient_is_not_already_a_friend
    if inviter && email.present? && inviter.friends.exists?(email: email)
      errors.add(:email, :already_friends)
    end
  end

  def acceptance_is_consistent
    if accepted_at.present? && invitee.nil?
      errors.add(:invitee, :blank)
    elsif invitee.present? && accepted_at.nil?
      errors.add(:accepted_at, :blank)
    end
  end

  def participants_are_different
    if inviter && email.present? && email == inviter.email
      errors.add(:email, :same_as_inviter)
    end

    if inviter_id && inviter_id == invitee_id
      errors.add(:invitee, :same_as_inviter)
    end
  end
end
