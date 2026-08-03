class User < ApplicationRecord
  extend FriendlyId

  USERNAME_FORMAT = /\A[a-zA-Z]([a-zA-Z0-9_]){3,31}\z/.freeze

  validates :username, format: { with: USERNAME_FORMAT, allow_blank: true }, presence: true, uniqueness: true

  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable, :confirmable, :lockable, :timeoutable, :trackable

  friendly_id :username

  def friendly_id
    attribute_in_database(friendly_id_config.query_field)
  end

  def normalize_friendly_id(value)
    value
  end
end
