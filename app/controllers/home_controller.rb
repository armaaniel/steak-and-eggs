class HomeController < ApplicationController
  before_action(:authenticate_user)
  before_action(:daily)
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
  
  def test
    @portfoliorecord = PortfolioRecord.where(user_id:current_user.id)  
  end  
  
end