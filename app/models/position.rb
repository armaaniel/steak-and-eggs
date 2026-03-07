class Position < ApplicationRecord
  belongs_to(:user)
  validates(:symbol, presence: true)
  validates(:symbol, uniqueness: { scope: :user_id })
  validates(:shares, numericality: { greater_than: 0 })
  validates(:average_price, numericality: { greater_than: 0 })
end
