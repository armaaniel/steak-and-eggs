class HomeController < ApplicationController
  layout "authenticated"
  
  def home
    @daily = PositionService.portfolio_records(user_id:current_user.id)
    
    result = PositionService.get_aum(user_id:current_user.id, balance:current_user.balance)
    
    @aum = result[:aum]
    
    @positions = result[:positions] || []
  rescue => e
    Sentry.capture_exception(e)
    redirect_to '/database_down' and return
  end
  
  def search
    
    results = Ticker.search(term:params[:q])
    render json: results
    
  end
  
  def activity
    @activity = PositionService.transactions(current_user: current_user)
  end
  
end