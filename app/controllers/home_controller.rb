class HomeController < ApplicationController
  before_action(:authenticate_user)
  before_action(:daily)
  before_action(:positions)
  before_action(:get_aum)
  layout "authenticated"
  
  def home
    
  end

  def search
    @results = MarketService.search(search_key: params[:search])
  end
  
  def activity
    @activity = PositionService.transactions(current_user: current_user)
  end
  
  def daily
    @daily = PositionService.portfolio_values(user_id:current_user.id)
  end
  
  def positions
    @positions = PositionService.positions(user_id:current_user.id) 
  end
  
  def get_aum
    result = PositionService.get_aum(user_id:current_user.id, balance:current_user.balance)
    @aum = result[:aum]
    @positions = result[:positions]
  end
  
end