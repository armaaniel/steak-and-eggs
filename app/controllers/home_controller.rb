class HomeController < ApplicationController
  before_action(:authenticate_user)
  layout "authenticated"
  
  def home
    @daily = PositionService.portfolio_records(user_id:current_user.id)
    result = PositionService.get_aum(user_id:current_user.id, balance:current_user.balance)
    @aum = result[:aum]
    @positions = result[:positions] || []
    @equity = PositionService.get_buying_power(user_id: current_user.id, balance: current_user.balance, used_margin: current_user.used_margin)&.dig(:equity_ratio)
  rescue => e
    Sentry.capture_exception(e)
    redirect_to '/database_down' and return
  end
  
  def search
    term = params[:q]
    
    if term.present?
      cached = RedisService.safe_get("search:#{term}")
      
      if cached
        render json: JSON.parse(cached, symbolize_names:true)
      else
      results = Ticker.where("symbol ILIKE ? OR name ILIKE ?", "#{term}%", "#{term}%")
      RedisService.safe_setex("search:#{term}", 1.hour.to_i, results.to_json)
      render json: results
      end
      
    else 
      render json: []
    end
  end
  
  def activity
    @activity = PositionService.transactions(current_user: current_user)
  end
  
end