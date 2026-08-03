class List < ApplicationRecord
  extend FriendlyId

  scope :ordered, -> { order(:order) }

  belongs_to :user, inverse_of: :lists

  validates :user_id, presence: true
  validates_associated :user
  validates :name, presence: true, length: { maximum: 255 }, uniqueness: true

  friendly_id :name, use: :slugged

  def should_generate_new_friendly_id?
    name_changed? || super
  end
end
