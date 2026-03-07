class PortfolioRecord < ApplicationRecord
  belongs_to(:user)
  validates(:date, uniqueness: { scope: :user_id })
  validates(:portfolio_value, numericality: { greater_than_or_equal_to: 0 })
end
