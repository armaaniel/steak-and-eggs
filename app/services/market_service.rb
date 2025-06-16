class MarketService
  def self.position(params:, current_user:)
    return if params[:quantity].blank? || params[:quantity].to_i < 0
    
    
    symbol = params[:symbol]
    market_price = marketdata(symbol:symbol)&.dig(:price)&.to_f
    
    return if market_price.nil? || market_price <=0
    
    trade_quantity = params[:quantity].to_i 
    trade_value = (trade_quantity * market_price)
    
    case params[:commit]
    when 'buy'
      ActiveRecord::Base.transaction do
        buying_power = PositionService.get_buying_power(user_id: current_user.id, balance: current_user.balance, used_margin: current_user.used_margin)
        record = Position.find_by(user_id:current_user.id, symbol: symbol)
        quantity_held = record.shares
        
        if current_user.balance >= trade_value
          current_user.balance -= trade_value
          current_user.save!
          if record
            record.update!(shares: (trade_quantity + quantity_held))
          else
            Position.create!(user_id: current_user.id, symbol: symbol, shares: trade_quantity)
          end
          
          Transaction.create!(symbol: symbol, quantity: trade_quantity, amount: trade_value, transaction_type: 'Buy', 
          user_id: current_user.id)
        
        elsif buying_power >= trade_value
          current_user.used_margin += current_user.balance
          current_user.balance = 0
          current_user.save!
          if record
            record.update!(shares: (trade_quantity + quantity_held))
          else 
            Position.create!(user_id: current_user.id, symbol: symbol, shares: trade_quantity)
          end 
          
          Transaction.create!(symbol: symbol, quantity: trade_quantity, amount: trade_value, transaction_type: 'Buy', 
          user_id: current_user.id)
        
        else
          return
        end
      end
      
    when 'sell'
      ActiveRecord::Base.transaction do
        record = Position.find_by(user_id:current_user.id, symbol: symbol)
        return if record.nil?
        quantity_held = record.shares
        return if quantity_held < trade_quantity
                
        margin_payment = [current_user.used_margin, trade_value].min
        current_user.used_margin -= margin_payment
        current_user.balance += (trade_value - margin_payment)
        current_user.save!
        
        if quantity_held == trade_quantity
          record.destroy!
        else 
          record.update!(shares: (quantity_held - trade_quantity))
        end
        
        Transaction.create!(symbol: symbol, quantity: trade_quantity, 
        amount: trade_value, transaction_type: 'Sell', user_id: current_user.id)
      end
    end
    
  rescue => e
    Rails.logger.error("Trade failed for #{symbol}, #{current_user.id}, #{e.message}")
    nil
  end
  
  
  def self.marketdata(symbol:)
    
    cached = safe_redis_get("price:#{symbol}")
    return JSON.parse(cached, symbolize_names: true) if cached
    
    stock_object = Alphavantage::TimeSeries.new(symbol: symbol)
    quote = stock_object.quote
    
    return {price:'N/A', open:'N/A', high:'N/A', low:'N/A', volume:'N/A'} unless quote
        
    resilient_data = {price: quote[:price] || 'N/A', open: quote[:open] || 'N/A', high: quote[:high] || 'N/A', low: quote[:low] || 'N/A', 
    volume: quote[:volume] || 'N/A'}
    
    safe_redis_setex("market:#{symbol}", 5.minutes.to_i, resilient_data.to_json)
    
    resilient_data
    
  rescue => e
    Rails.logger.error("Market data failed for #{symbol} #{e.message}")
    {price:'N/A', open:'N/A', high:'N/A', low:'N/A', volume:'N/A'}
  end
    
  def self.dailydata(symbol:)
    
    cached = safe_redis_get("daily:#{symbol}")
    return JSON.parse(cached, symbolize_names:true) if cached
    
    stock_object = Alphavantage::TimeSeries.new(symbol: symbol)
    
    daily = []
    stock_object.daily['time_series_daily']&.each do |date, values|
      daily.unshift({
        date: date,
        close: values['close'].to_f,
      })
      end
      
      safe_redis_setex("daily:#{symbol}", 24.hours.to_i, daily.to_json)
      
      daily
      
    rescue => e
      Rails.logger.error("Daily data failed for #{symbol}, #{e.message}")
      []
    end
  
  def self.companydata(symbol:)
    cached = safe_redis_get("company:#{symbol}")
    return JSON.parse(cached, symbolize_names:true) if cached
    
    company = Alphavantage::Fundamental.new(symbol: symbol).overview
    
    return {name:'N/A', currency:'N/A', :'52_week_high'=> 'N/A', exchange: 'N/A', :'52_week_low'=> 'N/A', market_capitalization:'N/A', 
      description: 'N/A'} unless company
    
    safe_redis_setex("company:#{symbol}", 24.hours.to_i, company.to_json)
    
    company
    
  rescue => e
    Rails.logger.error("Company data failed for #{symbol}, #{e.message}")
    {name:'N/A', currency:'N/A', :'52_week_high'=> 'N/A', exchange: 'N/A', :'52_week_low'=> 'N/A', market_capitalization:'N/A', 
      description: 'N/A'}
    
  end
  
  def self.exchange_rate
    cached = safe_redis_get("forex")
    return cached.to_f if cached
    
    forex = Alphavantage::Forex.new(from_symbol:'USD', to_symbol: 'CAD').exchange_rates&.dig('exchange_rate')
    
    unless forex
      Rails.logger.error("Can't get forex rate for USD to CAD")
      return 1.36
    end
    
    safe_redis_setex("forex", 5.minutes.to_i, forex)
    
    forex.to_f
    
  rescue => e
    Rails.logger.error("Can't get forex rate for USD to CAD, #{e.message}")
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
    Rails.logger.error("Search failed for #{search_key}, #{e.message}")
    []
    
  end
  
  private
  
  def self.safe_redis_get(key)
    REDIS.get(key)
  rescue Redis::BaseError
    nil
  end
  
  def self.safe_redis_setex(key, time, value)
    REDIS.setex(key, time, value)
  rescue Redis::BaseError
    nil
  end
  
end
