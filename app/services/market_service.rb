class MarketService
  class InsufficientFundsError < StandardError; end
  class InsufficientSharesError < StandardError; end
  class ApiError < StandardError; end
  
  Api_key = "BwLaqIrn3PJnY6NfIDBaEtsqycllj8lE"
  
  
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
        return cached
      end
      
      raise ApiError
    end
  end
  
  def self.marketdata(symbol:)
    
    payload = {symbol: symbol, used_redis:false, used_api:false}
    
    ActiveSupport::Notifications.instrument('MarketService.marketadata', payload) do
      cached = RedisService.safe_get("market:#{symbol}")
      
      if cached
        payload[:used_redis] = true
        return cached
      end
      
      payload[:used_api] = true
      
      uri=URI("https://api.polygon.io/v2/snapshot/locale/us/markets/stocks/tickers/#{symbol}?apiKey=#{Api_key}")
      response = Net::HTTP.get_response(uri)
      raise ApiError unless response.code == '200'

      body = JSON.parse(response.body)
      
      data = {open: body['ticker']['day']['o'], high: body['ticker']['day']['h'], low:body['ticker']['day']['l'], 
        volume:body['ticker']['day']['v']}
                
      RedisService.safe_setex("market:#{symbol}", 5.minutes.to_i, data.to_json)
      data    
    end    
  end
    
  def self.companydata(symbol:)
    
    payload = {symbol: symbol, used_redis: false, used_api: false}
    
    ActiveSupport::Notifications.instrument("MarketService.companydata", payload) do
      cached = RedisService.safe_get("company:#{symbol}")
      
      if cached
        payload[:used_redis] = true 
        return cached
      end
      
      payload[:used_api] = true
      
      uri=URI("https://api.polygon.io/v3/reference/tickers/#{symbol}?apiKey=#{Api_key}")
      response = Net::HTTP.get_response(uri)
      raise ApiError unless response.code == '200'
      
      body = JSON.parse(response.body)
      data = {market_cap: body['results']['market_cap'], description: body['results']['description']}    
      
      RedisService.safe_setex("company:#{symbol}", 3.days.to_i, data.to_json)
      data
    end
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
       
      uri=URI("https://api.polygon.io/v2/aggs/ticker/#{symbol}/range/1/day/#{Date.today-5.months}/#{Date.today}?apiKey=#{Api_key}")
      response=Net::HTTP.get_response(uri)
      raise ApiError unless response.code == '200'
      
      body=JSON.parse(response.body)
    
      data = body['results'].map do |result|
        time = Time.at(result['t']/1000).utc
        {date:time.strftime("%Y-%m-%d"), close: result['c']}
      end
      
      RedisService.safe_setex("daily:#{symbol}", 24.hours.to_i, data.to_json)
      data
    end
  end
  
end
