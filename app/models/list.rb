class List < ApplicationRecord
  extend FriendlyId

  NAME_FORMAT = /\A[A-Za-z0-9](?:[A-Za-z0-9[:punct:]]| (?=\S))*\z/.freeze

  scope :alphabetical, -> { order(:name) }
  scope :ordered, -> { order(:position) }
  scope :publicly_visible, -> { where(public: true) }

  belongs_to :user, inverse_of: :lists
  has_many :list_items, dependent: :destroy, inverse_of: :list

  validates :name,
            format: { with: NAME_FORMAT, allow_blank: true },
            presence: true,
            length: { minimum: 4, maximum: 255 },
            uniqueness: { scope: :user_id, case_sensitive: false }
  validates :description,
            length: { maximum: 1024 }
  validates :position,
            numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :public,
            inclusion: { in: [ true, false ] }

  before_validation :normalize_name
  before_validation :set_initial_position, on: :create

  friendly_id :name, use: [ :scoped, :slugged ], scope: :user

  def should_generate_new_friendly_id?
    name_changed? || super
  end

  private

  def normalize_name
    name&.squish!
  end

  def set_initial_position
    return unless position.nil?

    last_position = user.lists.maximum(:position)

    self.position = last_position ? last_position + 1 : 0
  end
end
