class MarketService
  class InsufficientFundsError < StandardError; end
  class InsufficientSharesError < StandardError; end
  
  
  def self.buy(symbol:, quantity:, user_id:, name:)
    raise(ArgumentError, "Invalid Quantity") if quantity.blank? || quantity.to_i <=0
    quantity = quantity.to_i
    
    stock_price = marketprice(symbol:symbol)
    raise(StandardError, "Unable to fetch Stock Price for #{symbol}") if stock_price.blank? || stock_price <=0
    
    trade_value = quantity*stock_price
    
    ActiveRecord::Base.transaction do
      user = User.lock.find(user_id)
      position = Position.lock.find_by(user_id:user_id, symbol: symbol)
      
      raise(InsufficientFundsError, "Insufficient funds for this purchase") if user.balance < trade_value
      
      user.balance -= trade_value
      user.save!
        
        if position
          new_quantity = (position.shares + quantity)
          new_average = ((position.shares * position.average_price) + trade_value) / new_quantity
          
          position.update!(average_price: new_average, shares: new_quantity)
        else
          Position.create!(user_id:user_id, symbol: symbol, shares: quantity, name: name, average_price:stock_price)
        end
        RedisService.safe_del("positions:#{user_id}")
        transaction = Transaction.create!(symbol: symbol, quantity: quantity, value: trade_value, transaction_type: 'Buy', user_id: user_id,
        market_price:stock_price)
        
        {symbol: transaction.symbol, quantity: transaction.quantity, value: transaction.value, 
          market_price: transaction.market_price}
      end
    
    end
  
  def self.sell(symbol:, quantity:, user_id:)
    raise(ArgumentError, "Invalid Quantity") if quantity.blank? || quantity.to_i <= 0
    quantity = quantity.to_i
    
    stock_price = marketprice(symbol:symbol)
    raise(StandardError, "Unable to fetch Stock Price for #{symbol}") if stock_price.blank? || stock_price <=0
    
    trade_value = quantity*stock_price
    
    ActiveRecord::Base.transaction do
      user = User.lock.find(user_id)
      position = Position.lock.find_by!(user_id:user_id, symbol: symbol)
      
      raise(InsufficientSharesError, "Invalid Quantity") if position.shares < quantity
      
      realized_pnl = (trade_value - (position.average_price * quantity))
      
      user.balance += trade_value
      user.save!
      
      if position.shares == quantity
        position.destroy!
      else
        position.update!(shares: position.shares - quantity)
      end
      RedisService.safe_del("positions:#{user_id}")
      transaction = Transaction.create!(symbol:symbol, quantity:quantity, value:trade_value, transaction_type:'Sell', user_id:user_id, 
      realized_pnl: realized_pnl, market_price:stock_price)
      
      {symbol: transaction.symbol, quantity: transaction.quantity, value: transaction.value, realized_pnl: transaction.realized_pnl,
        market_price: transaction.market_price}
    end
  
  end
    
  def self.marketprice(symbol:)
    
    payload = {symbol: symbol, used_redis: false, used_api: false}
    
    ActiveSupport::Notifications.instrument('MarketService.marketprice', payload) do
      cached = RedisService.safe_get("price:#{symbol}")
      
      if cached
        payload[:used_redis] = true
        return cached.to_f
      end
      
      payload[:used_api] = true
      
      stock_object = Alphavantage::TimeSeries.new(symbol: symbol)
      quote = stock_object.quote
      
      if quote&.dig(:price)
        RedisService.safe_setex("price:#{symbol}", 5.minutes.to_i, quote[:price])
        return quote[:price].to_f
      end
    
    0
    
  end
    
  rescue => e
    Sentry.capture_exception(e)
    'N/A'
    
  end
  
  def self.marketdata(symbol:)
    
    payload = {symbol: symbol, used_redis: false, used_api: false}
    
    ActiveSupport::Notifications.instrument('MarketService.marketdata', payload) do
      cached = RedisService.safe_get("market:#{symbol}")
      
      if cached
        payload[:used_redis] = true
        return JSON.parse(cached, symbolize_names: true)
      end
      
      payload[:used_api] = true
      
      stock_object = Alphavantage::TimeSeries.new(symbol: symbol)
      quote = stock_object.quote
      
      return {price:'N/A', open:'N/A', high:'N/A', low:'N/A', volume:'N/A'} unless quote
      
      resilient_data = {price: quote[:price] || 'N/A', open: quote[:open] || 'N/A', high: quote[:high] || 'N/A', low: quote[:low] || 'N/A', 
        volume: quote[:volume] || 'N/A'}
        
        RedisService.safe_setex("market:#{symbol}", 5.minutes.to_i, resilient_data.to_json)
        
        resilient_data
        
      end
    
  rescue => e
    Sentry.capture_exception(e)
    {price:'N/A', open:'N/A', high:'N/A', low:'N/A', volume:'N/A'}
  end
    
  def self.chartdata(symbol:)
    
    payload = {symbol: symbol, used_redis: false, used_api: false}
    
    ActiveSupport::Notifications.instrument("MarketService.chartdata", payload) do
      
      cached = RedisService.safe_get("daily:#{symbol}")
      if cached
        payload[:used_redis] = true
        return cached
      end
      
      payload[:used_api] = true
      
      data = Alphavantage::TimeSeries.new(symbol: symbol).daily
      
      daily = []
      data&.dig('time_series_daily')&.each do |date, values|
        daily.unshift({date: date, close: values['close'].to_f})
      end
      
      RedisService.safe_setex("daily:#{symbol}", 24.hours.to_i, daily.to_json)
      
      daily
      
    end
  
  rescue => e
    Sentry.capture_exception(e)
    []
  end
  
  def self.companydata(symbol:)
    
    payload = {symbol: symbol, used_redis: false, used_api: false}
    
    ActiveSupport::Notifications.instrument("MarketService.companydata", payload) do
      
      cached = RedisService.safe_get("company:#{symbol}")
      
      if cached
        payload[:used_redis] = true 
        return JSON.parse(cached, symbolize_names:true)
      end
      
      payload[:used_api] = true
      
      company = Alphavantage::Fundamental.new(symbol: symbol).overview
      
      return {name:'N/A', currency:'N/A', :'52_week_high'=> 'N/A', exchange: 'N/A', :'52_week_low'=> 'N/A', market_capitalization:'N/A', 
      description: 'N/A'} unless company[:name]
      
      RedisService.safe_setex("company:#{symbol}", 24.hours.to_i, company.to_json)
      
      company
      
    end
    
  rescue => e
    Sentry.capture_exception(e)
    {name:'N/A', currency:'N/A', :'52_week_high'=> 'N/A', exchange: 'N/A', :'52_week_low'=> 'N/A', market_capitalization:'N/A', 
      description: 'N/A'}
    
  end
  
  
  
end
