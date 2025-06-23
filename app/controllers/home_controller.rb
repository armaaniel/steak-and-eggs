class HomeController < ApplicationController
  before_action(:authenticate_user)
  layout "authenticated"
  
  def home
    @daily = PositionService.portfolio_values(user_id:current_user.id)
    result = PositionService.get_aum(user_id:current_user.id, balance:current_user.balance)
    @aum = result[:aum]
    @positions = result[:positions] || []
    @equity = PositionService.get_buying_power(user_id: current_user.id, balance: current_user.balance, used_margin: current_user.used_margin)&.dig(:equity_ratio)
  end

  def search
    @results = MarketService.search(search_key: params[:search])
  end
  
  def activity
    @activity = PositionService.transactions(current_user: current_user)
  end
  
end