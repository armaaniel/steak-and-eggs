class MarketService
  class InsufficientFundsError < StandardError; end
  class InsufficientSharesError < StandardError; end
  class ApiError < StandardError; end
    
  def self.buy(symbol:, quantity:, user_id:, name:)
    raise(ArgumentError) if quantity.blank? || quantity.to_i <=0
    quantity = quantity.to_i
    
    stock_price = RedisService.safe_get("price:#{symbol}")&.to_f
    raise(StandardError) if stock_price.blank? || stock_price <=0
    
    ActiveSupport::Notifications.instrument("MarketService.buy") do
        
      trade_value = quantity*stock_price
    
      ActiveRecord::Base.transaction do
        user = User.lock.find(user_id)
        position = Position.lock.find_by(user_id:user_id, symbol: symbol)
      
        raise(InsufficientFundsError) if user.balance < trade_value
      
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
          RedisService.safe_del("activity:#{user_id}")  
          transaction = Transaction.create!(symbol: symbol, quantity: quantity, value: trade_value, transaction_type: 'Buy', user_id: user_id,
          market_price:stock_price)
        
          {symbol: transaction.symbol, quantity: transaction.quantity, value: transaction.value, 
            market_price: transaction.market_price}
          end
        end
      end
  
  def self.sell(symbol:, quantity:, user_id:)
    raise(ArgumentError, "Invalid Quantity") if quantity.blank? || quantity.to_i <= 0
    quantity = quantity.to_i
    
    stock_price = RedisService.safe_get("price:#{symbol}")&.to_f
    raise(StandardError, "Unable to fetch Stock Price for #{symbol}") if stock_price.blank? || stock_price <=0
    
    ActiveSupport::Notifications.instrument("MarketService.sell") do
      
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
        RedisService.safe_del("activity:#{user_id}")  
        transaction = Transaction.create!(symbol:symbol, quantity:quantity, value:trade_value, transaction_type:'Sell', user_id:user_id, 
        realized_pnl: realized_pnl, market_price:stock_price)
      
        {symbol: transaction.symbol, quantity: transaction.quantity, value: transaction.value, realized_pnl: transaction.realized_pnl,
          market_price: transaction.market_price}
        end
      end
    end
  
  def self.marketprice(symbol:)
    
    ActiveSupport::Notifications.instrument("MarketService.marketprice", payload) do
      
      payload = {symbol: symbol, used_redis: false, used_db: false}
    
      cached_price = RedisService.safe_get("price:#{symbol}")
      cached_open = RedisService.safe_get("open:#{symbol}")
    
      if cached_price
        payload[:used_redis] = true
        return {price: cached_price, open: cached_open}
      end
    
      payload[:used_db] = true
      raise ApiError
    end
  end
  
  def self.marketdata(symbol:)
    
    payload = {symbol: symbol, used_redis:false, used_api:false}
    
    ActiveSupport::Notifications.instrument('MarketService.marketdata', payload) do
      cached = RedisService.safe_get("market:#{symbol}")
      
      if cached
        payload[:used_redis] = true
        return cached
      end
      
      payload[:used_api] = true
      
      uri=URI("https://api.polygon.io/v3/snapshot?ticker=#{symbol}&apiKey=#{ENV['API_KEY']}")
      response = Net::HTTP.get_response(uri)
      raise ApiError unless response.code == '200'
      
      body = JSON.parse(response.body)
      
      data = {open: body['results'][0]['session']['open'], high: body['results'][0]['session']['high'], 
        low:body['results'][0]['session']['low'], volume:body['results'][0]['session']['volume']}
        
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
      
      uri=URI("https://api.polygon.io/v3/reference/tickers/#{symbol}?apiKey=#{ENV['API_KEY']}")
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
      
      uri=URI("https://api.polygon.io/v2/aggs/ticker/#{symbol}/range/1/day/#{Date.current-5.months}/#{Date.current}?apiKey=#{ENV['API_KEY']}")
      response=Net::HTTP.get_response(uri)
      raise ApiError unless response.code == '200'
      
      body=JSON.parse(response.body)
      
      data = body['results'].map do |result|
        time = Time.at(result['t']/1000).utc
        {date:time.strftime("%Y-%m-%d"), value: result['c']}
      end
      
      RedisService.safe_setex("daily:#{symbol}", 24.hours.to_i, data.to_json)
      data
    end
  end
  
end
