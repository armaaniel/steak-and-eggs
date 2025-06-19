class HomeController < ApplicationController
  before_action(:authenticate_user)
  before_action(:daily)
  layout "authenticated"
  
  def home
    @positions = PositionService.positions(current_user: current_user)
  end

  def search
    @results = MarketService.search(search_key: params[:search])
  end
  
  def activity
    @activity = PositionService.transactions(current_user: current_user)
  end
  
  def daily
    data = PortfolioRecord.where(user_id:current_user.id).pluck(:date, :portfolio_value)
    @daily = data.map do |date, value| {date: date, value: value} end
  end    
  
end