class MarketService
  def self.position(params:, user_id:)
    return if params[:quantity].blank? || params[:quantity].to_i < 0
    
    
    symbol = params[:symbol]
    market_price = marketdata(symbol:symbol)&.dig(:price)&.to_f
    
    return if market_price.nil? || market_price <=0
    
    trade_quantity = params[:quantity].to_i 
    trade_value = (trade_quantity * market_price)
    
    case params[:commit]
    when 'buy'
      ActiveRecord::Base.transaction do
        user = User.lock.find(user_id)
        buying_power = PositionService.get_buying_power(user_id: user_id, balance: user.balance, used_margin: user.used_margin)[:buying_power]
        record = Position.find_by(user_id:user_id, symbol: symbol)
        quantity_held = record&.shares
        
        if user.balance >= trade_value
          user.balance -= trade_value
          user.save!
          if record
            record.update!(shares: (trade_quantity + quantity_held))
          else
            Position.create!(user_id: user_id, symbol: symbol, shares: trade_quantity, name: params&.dig(:name))
          end
          
          Transaction.create!(symbol: symbol, quantity: trade_quantity, amount: trade_value, transaction_type: 'Buy', 
          user_id: user_id)
        
        elsif buying_power >= trade_value
          user.used_margin += user.balance
          user.balance = 0
          user.save!
          if record
            record.update!(shares: (trade_quantity + quantity_held))
          else 
            Position.create!(user_id: user_id, symbol: symbol, shares: trade_quantity, name: params&.dig(:name))
          end 
          
          Transaction.create!(symbol: symbol, quantity: trade_quantity, amount: trade_value, transaction_type: 'Buy', 
          user_id: user_id)
        
        else
          return
        end
      end
      
    when 'sell'
      ActiveRecord::Base.transaction do
        user = User.lock.find(user_id)
        record = Position.find_by(user_id:user_id, symbol: symbol)
        return if record.nil?
        quantity_held = record.shares
        return if quantity_held < trade_quantity
                
        margin_payment = [user.used_margin, trade_value].min
        user.used_margin -= margin_payment
        user.balance += (trade_value - margin_payment)
        user.save!
        
        if quantity_held == trade_quantity
          record.destroy!
        else 
          record.update!(shares: (quantity_held - trade_quantity))
        end
        
        Transaction.create!(symbol: symbol, quantity: trade_quantity, 
        amount: trade_value, transaction_type: 'Sell', user_id: user_id)
      end
    end
    
    RedisService.safe_del("positions:#{user_id}")
  
  rescue => e
    Sentry.capture_exception(e)
    nil
  end
  
  def self.marketprice(symbol:)
    
    cached = RedisService.safe_get("price:#{symbol}")
    return cached.to_f if cached
    
    stock_object = Alphavantage::TimeSeries.new(symbol: symbol)
    quote = stock_object.quote
    
    if quote&.dig(:price)
      RedisService.safe_setex("price:#{symbol}", 5.minutes.to_i, quote[:price])
      return quote[:price].to_f
    end
    
    0
    
  rescue => e
    Sentry.capture_exception(e)
    'N/A'
    
  end
  
  def self.marketdata(symbol:)
    
    cached = RedisService.safe_get("market:#{symbol}")
    return JSON.parse(cached, symbolize_names: true) if cached
    
    stock_object = Alphavantage::TimeSeries.new(symbol: symbol)
    quote = stock_object.quote
    
    return {price:'N/A', open:'N/A', high:'N/A', low:'N/A', volume:'N/A'} unless quote
        
    resilient_data = {price: quote[:price] || 'N/A', open: quote[:open] || 'N/A', high: quote[:high] || 'N/A', low: quote[:low] || 'N/A', 
    volume: quote[:volume] || 'N/A'}
    
    RedisService.safe_setex("market:#{symbol}", 5.minutes.to_i, resilient_data.to_json)
    
    resilient_data
    
  rescue => e
    Sentry.capture_exception(e)
    {price:'N/A', open:'N/A', high:'N/A', low:'N/A', volume:'N/A'}
  end
    
  def self.dailydata(symbol:)
    
    cached = RedisService.safe_get("daily:#{symbol}")
    return JSON.parse(cached, symbolize_names:true) if cached
    
    stock_object = Alphavantage::TimeSeries.new(symbol: symbol)
    
    daily = []
    stock_object.daily['time_series_daily']&.each do |date, values|
      daily.unshift({
        date: date,
        close: values['close'].to_f,
      })
      end
      
      RedisService.safe_setex("daily:#{symbol}", 24.hours.to_i, daily.to_json)
      
      daily
      
    rescue => e
      Sentry.capture_exception(e)
      []
    end
  
  def self.companydata(symbol:)
    cached = RedisService.safe_get("company:#{symbol}")
    return JSON.parse(cached, symbolize_names:true) if cached
    
    company = Alphavantage::Fundamental.new(symbol: symbol).overview
    
    return {name:'N/A', currency:'N/A', :'52_week_high'=> 'N/A', exchange: 'N/A', :'52_week_low'=> 'N/A', market_capitalization:'N/A', 
      description: 'N/A'} unless company[:name]
    
    RedisService.safe_setex("company:#{symbol}", 24.hours.to_i, company.to_json)
    
    company
    
  rescue => e
    Sentry.capture_exception(e)
    {name:'N/A', currency:'N/A', :'52_week_high'=> 'N/A', exchange: 'N/A', :'52_week_low'=> 'N/A', market_capitalization:'N/A', 
      description: 'N/A'}
    
  end
  
  def self.exchange_rate
    cached = RedisService.safe_get("forex")
    return cached.to_f if cached
    
    forex = Alphavantage::Forex.new(from_symbol:'USD', to_symbol: 'CAD').exchange_rates&.dig('exchange_rate')
    
    unless forex
      Rails.logger.error("Can't get forex rate for USD to CAD")
      return 1.36
    end
    
    RedisService.safe_setex("forex", 5.minutes.to_i, forex)
    
    forex.to_f
    
  rescue => e
    Sentry.capture_exception(e)
    1.36
    
  end
  
  def self.search(search_key:)
    search = Alphavantage::TimeSeries.search(keywords: search_key)
    
    results = search.select do |n| 
      (n.region == 'United States' || n.region =='Toronto') &&
      (n.type == 'Equity' || n.type == 'ETF') &&
      !n.symbol.include?('.')
    end
    results
    
  rescue => e
    Sentry.capture_exception(e)
    []
    
  end
  
  private
  
  
  
  
  
end
