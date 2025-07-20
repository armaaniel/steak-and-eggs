class PositionService
  
  def self.find_positions(user_id:)
    
    cached = RedisService.safe_get("positions:#{user_id}")
    return JSON.parse(cached, symbolize_names:true) if cached
        
    position = Position.where(user_id: user_id)
    
    positions = position.map do |n| 
      {symbol: n.symbol, shares: n.shares, name: n.name}
    end
    
    RedisService.safe_setex("positions:#{user_id}", 24.hours.to_i, positions.to_json)
    
    positions
    
  rescue => e
    Sentry.capture_exception(e)
    nil
  end
  
  def self.transactions(current_user:)
    Transaction.where(user_id: current_user.id)
  end
  
  def self.find_position(symbol:, user_id:)
    position = Position.find_by(user_id: user_id, symbol: symbol)
  end
  
  def self.get_name(symbol:)
    Ticker.find_by(symbol:symbol)&.name&.split('.')&.first
  end
  
  def self.get_aum(user_id:, balance:)
    
    positions = PositionService.find_positions(user_id:user_id)
    
    return {aum:balance} if positions.empty?
    
    price_keys = positions.map {|n| "price:#{n[:symbol]}"}
    
    prices_array = REDIS.mget(*price_keys)
    
    zipped = positions.zip(prices_array)
    
    positions_with_prices = zipped.map do |position, price|
      position.merge(price: price.to_f)
    end
    
    aum = positions_with_prices.inject(balance) do |acc, position|
      price = position[:price].to_f
      acc + (price * position[:shares])
    end
    
    {aum:aum,positions:positions_with_prices}
    
  rescue => e
    Sentry.capture_exception(e)
    {aum:balance, positions:[]}
    
  end
  
  def self.get_buying_power(user_id:, balance:, used_margin:)
    
    portfolio_value = get_aum(user_id: user_id, balance: balance).dig(:aum)
    
    return 0 unless portfolio_value
    
    equity = portfolio_value - used_margin
    
    available_margin = (equity * 0.5) - used_margin
    
    buying_power = balance + available_margin
    
    if portfolio_value > 0 && portfolio_value != balance
      equity_ratio = (equity / (portfolio_value - balance) * 100).round(2)
    else
      equity_ratio = 100
    end
        
    { buying_power: buying_power.round(2),
      available_margin: available_margin.round(2),
      equity_ratio: equity_ratio,
      portfolio_value:portfolio_value
    }
    
  rescue => e
    Sentry.capture_exception(e)
    { buying_power: 0,
      available_margin: 0,
      equity_ratio: 0,
      portfolio_value:0
    }
  end
  
  def self.portfolio_records(user_id:)
    
    cached_values = RedisService.safe_get("portfolio:#{user_id}")
    return JSON.parse(cached_values, symbolize_names:true) if cached_values
  
    data = PortfolioRecord.where(user_id:user_id).pluck(:date, :portfolio_value)
    
    values = data.map do |date, value| 
      {date: date, value: value.to_f} 
    end
    
    if values.length < 2
      values = [{date:Date.today, value:values.first[:value]},{date:Date.today, value:values.first[:value]}]
    end
    
    RedisService.safe_setex("portfolio:#{user_id}", 6.hours.to_i, values.to_json)
    
    values
    
  rescue => e
    Sentry.capture_exception(e)
    []
  end
  
end
  
    