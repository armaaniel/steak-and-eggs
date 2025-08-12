class HomeController < ApiController
  before_action(:verify_token)
  
  def search
    results = Ticker.search(term:params[:q])
    render(json: results)
  end
  
  def get_portfolio_chart_data
    results = PositionService.portfolio_records(user_id:@current_user.id)
    render(json: results)
  end
  
  def get_portfolio_data
    result = PositionService.get_aum(user_id:@current_user.id, balance:@current_user.balance)
    render(json: result)
  end
  
  def get_activity_data
    data = Transaction.get(user_id:@current_user.id)
    render(json: data)
  end
  
end