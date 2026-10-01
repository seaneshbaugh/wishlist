class Purchase < ApplicationRecord
  scope :revealed, -> { where("reveal_at <= ?", Time.current) }
  scope :unrevealed, -> { where("reveal_at > ?", Time.current) }
  scope :anonymous, -> { where(anonymous: true) }
  scope :identified, -> { where(anonymous: false) }

  belongs_to :list_item, inverse_of: :purchases
  belongs_to :user, inverse_of: :purchases
  has_one :list, through: :list_item

  validates :purchased_from,
            length: { maximum: 512 }
  validates :notes,
            length: { maximum: 1024 }
  validates :price,
            numericality: { allow_nil: true, greater_than_or_equal_to: 0 }
  validates :quantity,
            numericality: { greater_than: 0, only_integer: true },
            presence: true
  validates :reveal_at,
            presence: true
  validates :anonymous,
            inclusion: { in: [ true, false ] }

  validate :quantity_does_not_exceed_remaining_quantity

  def revealed?
    reveal_at <= Time.current
  end

  def editable_by?(user)
    user_id == user.id && !revealed?
  end

  def deletable_by?(user)
    (user_id == user.id && !revealed?) || (list_item.list.user_id == user.id && revealed?)
  end

  private

  def quantity_does_not_exceed_remaining_quantity
    return unless list_item && quantity

    purchased_quantity = list_item.purchases.where.not(id: id).sum(:quantity)

    if purchased_quantity + quantity > list_item.quantity
      errors.add(:quantity, :exceeds_remaining_quantity)
    end
  end
end
