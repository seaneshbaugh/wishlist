class List < ApplicationRecord
  extend FriendlyId

  NAME_FORMAT = /\A[A-Za-z0-9](?:[A-Za-z0-9[:punct:]]| (?=\S))*\z/.freeze

  scope :alphabetical, -> { order(:name) }
  scope :ordered, -> { order(:order) }
  scope :publicly_visible, -> { where(public: true) }

  belongs_to :user, inverse_of: :lists

  validates :user_id, presence: true
  validates_associated :user
  validates :name,
            format: { with: NAME_FORMAT, allow_blank: true },
            presence: true,
            length: { minimum: 4, maximum: 255 },
            uniqueness: { scope: :user_id, case_sensitive: false }
  validates :description, length: { maximum: 1024 }
  validates :public, inclusion: { in: [ true, false ] }

  before_validation :normalize_name

  friendly_id :name, use: [ :scoped, :slugged ], scope: :user

  def should_generate_new_friendly_id?
    name_changed? || super
  end

  private

  def normalize_name
    name&.squish!
  end
end
