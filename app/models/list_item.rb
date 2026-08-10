class ListItem < ApplicationRecord
  enum :priority, {
    highest: 0,
    high: 1,
    medium: 2,
    low: 3,
    lowest: 4
  }, prefix: true

  scope :ordered, -> { order(:priority, :position) }
  scope :visible, -> { where(visible: true) }

  belongs_to :list, inverse_of: :list_items
  has_one :user, through: :list

  validates :name,
            length: { maximum: 255 },
            presence: true
  validates :notes,
            length: { maximum: 512 }
  validates :url,
            length: { maximum: 2048 },
            url: { allow_blank: true }
  validates :price,
            numericality: { allow_nil: true, greater_than_or_equal_to: 0 }
  validates :quantity,
            numericality: { greater_than: 0, only_integer: true }
  validates :position,
            numericality: { greater_than_or_equal_to: 0, only_integer: true  }
  validates :visible,
            inclusion: { in: [ true, false ] }

  before_validation :normalize_name

  private

  def normalize_name
    name&.squish!
  end
end
