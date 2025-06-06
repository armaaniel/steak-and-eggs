class StocksController < ApplicationController
  before_action(:authenticate_user)
  before_action(:get_data)
  layout 'authenticated'
  def show
    
  end
    
  def position
    MarketService.position(params: params, record: @record, current_user: current_user)
    
    redirect_to "/stocks/#{params[:symbol]}"
  end
  
  private
  
  def get_data
    @marketdata = MarketService.marketdata(params: params)
    @companydata = MarketService.companydata(params: params) 
    @record = PositionService.record(params: params, current_user: current_user)
    @daily = MarketService.daily(params: params)
  end
  
end  
