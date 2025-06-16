class StocksController < ApplicationController
  before_action(:authenticate_user)
  before_action(:get_data)
  layout 'authenticated'
  def show
    
  end
    
  def position
    MarketService.position(params: params, current_user: current_user)
    
    redirect_to "/stocks/#{params[:symbol]}"
  end
  
  private
  
  def get_data
    
    @marketdata = MarketService.marketdata(symbol: params[:symbol])
    
    
    @daily = MarketService.dailydata(symbol: params[:symbol])
    @companydata = MarketService.companydata(symbol: params[:symbol]) 
    @record = PositionService.record(symbol: params[:symbol], user_id: current_user.id)
    
    if @companydata[:currency] == 'USD'
      @exchangerate = MarketService.exchange_rate
    else
      @exchangerate = 1.0
    end
    
  end
  
end  
