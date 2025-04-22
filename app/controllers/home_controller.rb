class HomeController < ApplicationController
  before_action(:authenticate_user)
  layout "authenticated"
  def home
    name_object = 
    positions = Position.where(user_id: current_user.id)
    @positions = positions.map do |n| 
      {symbol: n.symbol, shares: n.shares, name: Alphavantage::Fundamental.new(symbol:n.symbol).overview.name}
    end
    
  end
  
  def search
    results = Alphavantage::TimeSeries.search(keywords: (params[:search]))
    @results = results.select do |n| 
     (n.region == 'United States' || n.region =='Toronto') &&
     (n.type == 'Equity' || n.type == 'ETF') &&
     !n.symbol.include?('.')
   end
    
  end
  
  def activity
    @activity = Transaction.where(user_id: current_user.id)
  end
  
end