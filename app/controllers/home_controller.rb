class HomeController < ApiController
  before_action(:authenticate_user_two)
  
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
    positions = result[:positions] || []
    render(json: {aum: result[:aum], positions: positions, balance: @current_user.balance})
  end
  
  def get_activity_data
    data = Transaction.get(user_id:@current_user.id)
    render(json: data)
  rescue => e
    render(json: {error: "An unexpected error occurred"}, status: 500)
  end
  
end