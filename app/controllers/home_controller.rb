class HomeController < ApiController
  before_action(:verify_token)
  
  def search
    results = Ticker.search(term:params[:q])
    render(json: results)
    
  rescue => e
    Sentry.capture_exception(e)
    render(json:[], status:503)
  end
  
  def get_portfolio_chart_data
    results = PositionService.portfolio_records(user_id:@current_user.id)
    render(json: results)
    
  rescue => e
    Sentry.capture_exception(e)
    render(json:[{date:Date.current, value:0.00},{date:Date.current,value:0.00}], status:503)
  end
  
  def get_portfolio_data
    result = PositionService.get_aum(user_id:@current_user.id, balance:@current_user.balance)
    render(json: result)
    
  rescue => e
    Sentry.capture_exception(e)
    render(json:{aum: 'N/A', balance:'N/A'}, status:503)
  end
  
  def get_activity_data
    data = Transaction.get(user_id:@current_user.id)    
    render(json: data)
    
  rescue => e
    Sentry.capture_exception(e)
    render(json: [], status: 503)
  end
  
end