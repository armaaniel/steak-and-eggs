class StocksController < ApiController
  before_action(:authenticate_user_two)
  
  def buy
    success = MarketService.buy(symbol:params[:symbol], user_id:@current_user.id, quantity:params[:quantity], 
    name:params[:name])
    
    if success
      render(json: {value: success[:value], quantity: success[:quantity], status: 201})
    else
      render(json: {error: "Trade Processing Failed"}, status: 500)
    end
     
  rescue MarketService::InsufficientFundsError => e
    render(json: {error: e.message}, status: 402) 
  rescue => e
    render(json: {error: "An unexpected error occurred"}, status: 500)
  end
  
  def sell
    success = MarketService.sell(symbol:params[:symbol], user_id:@current_user.id, quantity:params[:quantity])
    
    if success
      render(json: {value: success[:value], quantity: success[:quantity], status: 201})
    else
      render(json: {error: "Trade Processing Failed"}, status: 500)
    end
     
  rescue MarketService::InsufficientSharesError => e
    render(json: {error: e.message}, status: 402)
  rescue => e
    render(json: {error: "An unexpected error occurred"}, status: 500)   
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
  end
  
  def get_company_data
    data = MarketService.companydata(symbol:params[:symbol])
    render(json: data)
  end
  
  def get_market_data
    data = MarketService.marketdata(symbol:params[:symbol])
    render(json: data)
  end
  
  def get_user_data
  
    data = PositionService.find_position(symbol: params[:symbol], user_id: @current_user.id)
    
    if data
      render(json: {position: [data], balance: @current_user.balance})
    else
      render(json: {position: nil, balance: @current_user.balance})
    end
    
  rescue => e
    Sentry.capture_exception(e)
  end
  
  def get_stock_price
    data = MarketService.marketprice(symbol:params[:symbol])
    
    render(json:data)
  end
      
end
