class Transaction < ApplicationRecord
  belongs_to(:user)
  validates(:quantity, :amount, :transaction_type, :symbol, presence: true)
  validates(:quantity, :amount, numericality: { greater_than: 0 })
  
  enum(:transaction_type, {
      
    Deposit:0,
    Withdrawal:1,
    Buy:2,
    Sell:3
  
  }) 
  
end
