class Transaction < ApplicationRecord
  belongs_to(:user)
  validates(:quantity, :amount, :transaction_type, presence: true)
  validates(:quantity, :amount, numericality: { greater_than: 0 })
  validates(:transaction_type, inclusion: { in: ['Buy', 'Sell', 'Deposit', 'Withdraw'] })
end
