class User < ApplicationRecord
  extend FriendlyId

  USERNAME_FORMAT = /\A[a-zA-Z]([a-zA-Z0-9_]){3,31}\z/.freeze

  scope :alphabetical, -> { order(:username) }

  has_many :lists, dependent: :destroy, inverse_of: :user
  has_many :purchases, dependent: :destroy, inverse_of: :user
  has_many :outgoing_friendships, class_name: "Friendship", foreign_key: :requester_id,
           dependent: :destroy, inverse_of: :requester
  has_many :incoming_friendships, class_name: "Friendship", foreign_key: :recipient_id,
           dependent: :destroy, inverse_of: :recipient
  has_many :sent_invitations, class_name: "Invitation", foreign_key: :inviter_id,
           dependent: :destroy, inverse_of: :inviter
  has_many :accepted_invitations, class_name: "Invitation", foreign_key: :invitee_id,
           dependent: :destroy, inverse_of: :invitee

  validates :username,
            format: { allow_blank: true, with: USERNAME_FORMAT },
            presence: true,
            uniqueness: { case_sensitive: false }

  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable, :confirmable, :lockable, :timeoutable, :trackable

  friendly_id :username

  def friends
    User.where(id: outgoing_friendships.accepted.select(:recipient_id))
      .or(User.where(id: incoming_friendships.accepted.select(:requester_id)))
  end

  def friendly_id
    attribute_in_database(friendly_id_config.query_field)
  end

  def normalize_friendly_id(value)
    value
  end

  protected

  def send_devise_notification(notification, *args)
    ActiveRecord.after_all_transactions_commit do
      devise_mailer.public_send(notification, self, *args).deliver_later
    end
  end
end
