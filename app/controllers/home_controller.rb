class HomeController < ApplicationController
  before_action(:authenticate_user)
  layout "authenticated"
  
  def home
    @daily = PositionService.portfolio_values(user_id:current_user.id)
    result = PositionService.get_aum(user_id:current_user.id, balance:current_user.balance)
    @aum = result[:aum]
    @positions = result[:positions] || []
    @equity = PositionService.get_buying_power(user_id: current_user.id, balance: current_user.balance, used_margin: current_user.used_margin)&.dig(:equity_ratio)
  rescue => e
    redirect_to '/database_down' and return
  end
  
  def search
    term = params[:q]
    
    if term.present?
      results = Ticker.where("symbol ILIKE ? OR name ILIKE ?", "#{term}%", "#{term}%")
      render json: results
    else 
      render json: []
    end
  end
  
  def activity
    @activity = PositionService.transactions(current_user: current_user)
  end
  
end