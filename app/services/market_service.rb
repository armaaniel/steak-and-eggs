class MarketService
  def self.position(params:, record:, current_user:)
    return if params[:quantity].blank? || params[:quantity].to_i < 0
    
    
    symbol = params[:symbol]
    market_price = REDIS.get(symbol).to_f
    trade_quantity = params[:quantity].to_i 
    trade_value = (trade_quantity * market_price)
    
    case params[:commit]
    when 'buy'

      buying_power = PositionService.get_buying_power(user_id: current_user.id, balance: current_user.balance, used_margin: current_user.used_margin)
      
      
      if current_user.balance >= trade_value
        current_user.balance -= trade_value
        current_user.save
        if record
          record.update(shares: (trade_quantity + record[:shares]))
        else
          Position.create(user_id: current_user.id, symbol: symbol, shares: trade_quantity)
        end
        
        Transaction.create(symbol: symbol, quantity: trade_quantity, amount: trade_value, transaction_type: 'Buy', 
        user_id: current_user.id)
        
      elsif buying_power >= trade_value
        current_user.used_margin += current_user.balance
        current_user.balance = 0
        current_user.save
        if record
          record.update(shares: (trade_quantity + record[:shares]))
        else 
          Position.create(user_id: current_user.id, symbol: symbol, shares: trade_quantity)
        end 
        
        Transaction.create(symbol: symbol, quantity: trade_quantity, amount: trade_value, transaction_type: 'Buy', 
        user_id: current_user.id)
              
      end
      
    when 'sell'
      return if record.nil?
      if record[:shares] == trade_quantity
        current_user.balance += trade_value
        current_user.save
        record.destroy()
      elsif record[:shares] > trade_quantity
        current_user.balance += trade_value
        current_user.save
        record.update(shares: (record[:shares] - trade_quantity))
      end
      Transaction.create(symbol: symbol, quantity: trade_quantity, 
      amount: trade_value, transaction_type: 'Sell', user_id: current_user.id)
    end
  end
  
  def self.marketdata(params:)
    stock_object = Alphavantage::TimeSeries.new(symbol: params[:symbol])
    stock_object.quote
  end
  
  def self.companydata(params:)
    Alphavantage::Fundamental.new(symbol: params[:symbol]).overview
  end
  
  def self.daily(params:)
    daily = []
    stock_object = Alphavantage::TimeSeries.new(symbol: params[:symbol])
    stock_object&.daily['time_series_daily']&.each do |date, values|
      daily.unshift({
        date: date,
        close: values['close'].to_f,
      })
    end
    daily
  end
  
  def self.search(params:)
    search = Alphavantage::TimeSeries.search(keywords: (params[:search]))
    
    results = search.select do |n| 
      (n.region == 'United States' || n.region =='Toronto') &&
      (n.type == 'Equity' || n.type == 'ETF') &&
      !n.symbol.include?('.')
    end
    results
  end
end
