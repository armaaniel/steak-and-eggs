class HomeController < ApplicationController
  before_action(:authenticate_user)
  layout "authenticated"
  
  def home
    @positions = PositionService.positions(current_user: current_user)
  end

  def search
    @results = MarketService.search(params: params)
  end
  
  def activity
    @activity = PositionService.transactions(current_user: current_user)
  end
  
end