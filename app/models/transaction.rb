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
    payload = {used_redis:false, used_db:false}

    ActiveSupport::Notifications.instrument("Transaction.get", payload) do
      cached = RedisService.safe_get("activity:#{user_id}")

      if cached
        payload[:used_redis] = true
        return cached
      end

      payload[:used_db] = true

      data = Transaction.where(user_id: user_id).order(created_at: :desc)

      values = data.map do |transaction|
        {id: transaction.id, value: transaction.value, quantity: transaction.quantity, symbol: transaction.symbol,
          transaction_type: transaction.transaction_type, date: transaction.created_at.strftime("%m/%d/%Y %I:%M %p"),
          market_price:transaction.market_price, realized_pnl:transaction.realized_pnl}
      end

      RedisService.safe_setex("activity:#{user_id}", 6.hours.to_i, values.to_json)

      values
    end
  end
end
