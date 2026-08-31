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
  scope :visible_to, ->(user) {
    joins(:list)
    .where(
      <<~SQL.squish,
        "lists"."user_id" = :user_id
        OR (
          "list_items"."visible" = TRUE
          AND (
            EXISTS (
              SELECT 1
              FROM "purchases"
              WHERE "purchases"."list_item_id" = "list_items"."id"
              AND "purchases"."user_id" = :user_id
            )
            OR (
              COALESCE(
                (
                  SELECT SUM("purchases"."quantity")
                  FROM "purchases"
                  WHERE "purchases"."list_item_id" = "list_items"."id"
                ),
                0
              ) < "list_items"."quantity"
            )
          )
        )
      SQL
      user_id: user.id
    )
  }

  belongs_to :list, inverse_of: :list_items
  has_one :user, through: :list
  has_many :purchases, dependent: :destroy, inverse_of: :list_item

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
  before_validation :set_initial_position, on: :create

  def purchase_for(user)
    purchases.find { |purchase| purchase.user_id == user.id }
  end

  def purchased?
    purchases.any?(&:revealed?)
  end

  def revealed_purchase_quantity
    purchases.select(&:revealed?).sum(&:quantity)
  end

  private

  def normalize_name
    name&.squish!
  end

  def set_initial_position
    return if !position.nil? || priority.nil?

    last_position = list.list_items.where(priority: priority).maximum(:position)

    self.position = last_position ? last_position + 1 : 0
  end
end
