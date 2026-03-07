require 'rails_helper'

RSpec.describe(MarketService) do
  let(:user) { create(:user) }
  
  before do
    allow(RedisService).to(receive(:safe_get).with("price:TSLA").and_return("100"))
    allow(RedisService).to(receive(:safe_del))
  end
  
  describe("buy") do
    it("creates a position and deducts balance") do
      result = MarketService.buy(symbol: "TSLA", quantity: 10, user_id: user.id, name: "Tesla, Inc.")
      
      expect(user.reload.balance).to(eq(9000))
      
      position = Position.find_by(user_id: user.id, symbol: "TSLA")
      expect(position.shares).to(eq(10))
      expect(position.average_price).to(eq(100))
      
      transaction = Transaction.find_by(symbol:"TSLA", user_id:user.id)
      expect(transaction.quantity).to(eq(10))
      expect(transaction.value).to(eq(1000))
      expect(transaction.market_price).to(eq(100))
      expect(transaction.transaction_type).to(eq("Buy"))
      
      expect(result[:symbol]).to(eq("TSLA"))
      expect(result[:quantity]).to(eq(10))
      expect(result[:value]).to(eq(1000))
      expect(result[:market_price]).to(eq(100))
    end
  end
end
      
      