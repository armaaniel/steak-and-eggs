class HomeController < ApplicationController
  before_action(:authenticate_user)
  layout "authenticated"
  def home
    positions = Position.where(user_id: current_user.id)
    @positions = positions.map {|n| {symbol: n.symbol, shares: n.shares}}
    
  end
  
  def search
    
    finnhub_client ||= FinnhubRuby::DefaultApi.new
    search = finnhub_client.symbol_search(params[:search])
    filtered_search = search.result.select {|n| (n.type == 'Common Stock' || n.type == 'ETP') && !n.symbol.include?('.')}
    @results = filtered_search.map {|n| {symbol: n.symbol, description: n.description}}
  end
  
  def activity
    @activity = Transaction.where(user_id: current_user.id)
  end
  
end