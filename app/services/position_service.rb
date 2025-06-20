class PositionService
  def self.positions(current_user:)
    position = Position.where(user_id: current_user.id)
    positions = position.map do |n| 
      {symbol: n.symbol, shares: n.shares, name: MarketService.companydata(symbol:n.symbol)&.dig(:name), 
        price: MarketService.marketprice(symbol:n.symbol)}
    end
  rescue => e
    Sentry.capture_exception(e)
    nil
  end
  
  def self.transactions(current_user:)
    Transaction.where(user_id: current_user.id)
  end
  
  def self.record(symbol:, user_id:)
    Position.find_by(user_id: user_id, symbol: symbol)
  end
  
  def self.get_aum(user_id:, balance:)
    positions = Position.where(user_id: user_id).to_a
    
    return balance if positions.empty?
    
    price_keys = positions.map {|n| "price:#{n.symbol}"}
    
    prices_array = REDIS.mget(*price_keys)
    
    symbols = positions.pluck(:symbol)
    
    prices = symbols.zip(prices_array).to_h
    
    positions.inject(balance) do |acc, position|
      price = prices[position.symbol].to_f
      acc + (price * position.shares)
    end
    
  rescue => e
    Sentry.capture_exception(e)
    nil
    
  end
  
  def self.get_buying_power(user_id:, balance:, used_margin:)
    
    portfolio_value = get_aum(user_id: user_id, balance: balance)
    
    return nil unless portfolio_value
    
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
      equity_ratio: equity_ratio,
      portfolio_value:portfolio_value
    }
    
  rescue => e
    Sentry.capture_exception(e)
    nil
  end
  
  def self.portfolio_values(user_id:)
    
    begin
      cached_values = REDIS.get("portfolio:#{user_id}")
      return JSON.parse(cached_values, symbolize_names:true) if cached_values
    rescue Redis::BaseError
      Sentry.capture_exception(e)
      []
    end
    
    data = PortfolioRecord.where(user_id:user_id).pluck(:date, :portfolio_value)
    
    values = data.map do |date, value| 
      {date: date, value: value.to_f} 
    end
    
    if values.length < 2
      values = [{date:Date.today, value:values.first[:value]},{date:Date.today, value:values.first[:value]}]
    end
    
    begin
      REDIS.setex("portfolio:#{user_id}", 6.hours.to_i, values.to_json)
    rescue Redis::BaseError
      Sentry.capture_exception(e)
    end
    
    values
    
  rescue => e
    Sentry.capture_exception(e)
    []
  end
    
end
  
    