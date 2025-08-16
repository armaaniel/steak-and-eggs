class StocksController < ApiController
  before_action(:verify_token)
  
  def buy
    data = MarketService.buy(symbol:params[:symbol], user_id:@current_user.id, quantity:params[:quantity], 
    name:params[:name])
    
    render(json: data, status: 201)
     
  rescue MarketService::InsufficientFundsError => e
    Sentry.capture_exception(e)
    render(json: {error: e.message}, status: 402) 
  end
  
  def sell
    data = MarketService.sell(symbol:params[:symbol], user_id:@current_user.id, quantity:params[:quantity])
    
    render(json: data, status: 201)
     
  rescue MarketService::InsufficientSharesError => e
    Sentry.capture_exception(e)
    render(json: {error: e.message}, status: 402)
  end
  
  def get_ticker_data
    result = Ticker.query(symbol: params[:symbol])
    
    if result[:success]
      render(json: result[:data])
    else
      render(json: {error: 'Symbol not found'}, status:404)
    end
  end
  
  def get_chart_data
    data = MarketService.chartdata(symbol:params[:symbol])
    render(json:data)
    
  rescue MarketService::ApiError => e
    Sentry.capture_exception(e)
    data = [{date:Date.today, close:0},{date:Date.today,close:0}]
    render(json:data)  
  end
  
  def get_company_data
    data = MarketService.companydata(symbol:params[:symbol])
    render(json: data)
  end
  
  def get_market_data
    data = MarketService.marketdata(symbol:params[:symbol])
    puts data
    render(json: data)
    
  rescue MarketService::ApiError => e
    Sentry.capture_exception(e)
    data = {open:0, high: 0, low: 0, volume: 0}
    render(json:data)
    puts 'yo'
  end
    
  def get_user_data
  
    data = PositionService.find_position(symbol: params[:symbol], user_id: @current_user.id)
    
    if data
      render(json: {position: data, balance: @current_user.balance})
    else
      render(json: {position: nil, balance: @current_user.balance})
    end
    
  end
  
  def get_stock_price
    data = MarketService.marketprice(symbol:params[:symbol])
    render(json:data)
    
  rescue MarketService::ApiError => e
    Sentry.capture_exception(e)
    render(json:{price:0, open:0})        
  end
      
end
