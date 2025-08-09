class Transaction < ApplicationRecord
  belongs_to(:user)
  validates(:quantity, :value, :transaction_type, :symbol, presence: true)
  validates(:quantity, :value, numericality: { greater_than: 0 })
  
  enum(:transaction_type, {
      
    Deposit:0,
    Withdraw:1,
    Buy:2,
    Sell:3
  
  })
  
  def self.get(user_id:)
    data = Transaction.where(user_id: user_id).order(created_at: :desc)
    
    data.map do |transaction|
      {id: transaction.id, value: transaction.value.round(2), quantity: transaction.quantity, symbol: transaction.symbol,
        transaction_type: transaction.transaction_type, date: transaction.created_at.strftime("%m/%d/%Y %I:%M %p")}
      end
        
  rescue => e
    Sentry.capture_exception(e)
    raise
  end
  
end
