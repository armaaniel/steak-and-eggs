class PositionService
  def self.positions(current_user:)
    position = Position.where(user_id: current_user.id)
    positions = position.map do |n| 
      {symbol: n.symbol, shares: n.shares, name: Alphavantage::Fundamental.new(symbol:n.symbol).overview.name}
    end
    positions
  end
  
  def self.transactions(current_user:)
    Transaction.where(user_id: current_user.id)
  end
  
  def self.record(params:, current_user:)
    Position.find_by(user_id: current_user.id, symbol: params[:symbol])
  end
  
  def self.get_aum(user_id:, balance:)
    positions = Position.where(user_id: user_id).to_a
    
    return balance if positions.empty?
    
    symbols = positions.pluck(:symbol)
    prices_array = REDIS.mget(*symbols)
    prices = symbols.zip(prices_array).to_h
    
    positions.inject(balance) do |acc, position|
      price = prices[position.symbol].to_f
      acc + (price * position.shares)
    end
    
  end
  
  def self.get_buying_power(user_id:, balance:, used_margin:)
    
    portfolio_value = get_aum(user_id: user_id, balance: balance)
    
    equity = portfolio_value - used_margin
    
    available_margin = (equity * 0.5) - used_margin
    
    buying_power = balance + available_margin
    
    if portfolio_value > 0
      equity_ratio = (equity / (portfolio_value - balance) * 100).round(2)
    else
      equity_ratio = 100
    end
        
    { buying_power: buying_power,
      available_margin: available_margin,
      equity_ratio: equity_ratio
    }
    
  end
  
end
  
    