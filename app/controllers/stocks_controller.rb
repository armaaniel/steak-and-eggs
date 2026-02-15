class StocksController < ApiController
  before_action(:verify_token)

  def buy
    data = MarketService.buy(symbol:params[:symbol], user_id:@current_user.id, quantity:params[:quantity],
    name:params[:name])

    render(json: data, status: 201)

  rescue MarketService::InsufficientFundsError => e
    Sentry.capture_exception(e)
    render(json: {error: "Insufficient funds for this transaction"}, status: 402)
  rescue => e
    Sentry.capture_exception(e)
    render(json:{error: "Service temporarily unavailable"}, status:503)
  end

  def sell
    data = MarketService.sell(symbol:params[:symbol], user_id:@current_user.id, quantity:params[:quantity])

    render(json: data, status: 201)

  rescue MarketService::InsufficientSharesError => e
    Sentry.capture_exception(e)
    render(json: {error: "Insufficient shares for this transaction"}, status: 402)
  rescue => e
    Sentry.capture_exception(e)
    render(json:{error:"Service temporarily unavailable"}, status:503)
  end

  def get_ticker_data
    data = Ticker.query(symbol: params[:symbol])

    if data
      render(json: data)
    else
      head(:not_found)
    end

  rescue => e
    Sentry.capture_exception(e)
    head(:not_found)
  end

  def get_chart_data
    data = MarketService.chartdata(symbol:params[:symbol])
    render(json:data)

  rescue => e
    Sentry.capture_exception(e)
    render(json:[{date:Date.current, value:0}, {date:Date.current, value:0}], status:503)
  end

  def get_company_data
    data = MarketService.companydata(symbol:params[:symbol])
    render(json: data)

  rescue => e
    Sentry.capture_exception(e)
    render(json:{market_cap:'N/A', description:'N/A'}, status:503)
  end

  def get_market_data
    data = MarketService.marketdata(symbol:params[:symbol])
    render(json: data)

  rescue => e
    Sentry.capture_exception(e)
    render(json:{open:'N/A', high: 'N/A', low: 'N/A', volume: 'N/A', last: 'N/A'}, status:503)
  end

  def get_user_data
    data = PositionService.find_position(symbol: params[:symbol], user_id: @current_user.id)

    if data
      render(json: {position: data, balance: @current_user.balance})
    else
      render(json: {balance: @current_user.balance})
    end

  rescue => e
    Sentry.capture_exception(e)
    render(json: {balance: 'N/A'}, status:503)
  end

  def get_stock_price
    data = MarketService.marketprice(symbol:params[:symbol])
    render(json:data)

  rescue => e
    Sentry.capture_exception(e)
    render(json:{price:"N/A", open:"N/A"}, status:503)
  end
end
