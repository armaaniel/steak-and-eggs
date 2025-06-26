class StocksController < ApplicationController
  before_action(:authenticate_user)
  before_action(:get_data)
  layout 'authenticated'
  def show
    
    if @marketdata == {price:'N/A', open:'N/A', high:'N/A', low:'N/A', volume:'N/A'} &&
      @companydata == {name:'N/A', currency:'N/A', :'52_week_high'=> 'N/A', exchange: 'N/A', :'52_week_low'=> 'N/A', market_capitalization:'N/A', 
      description: 'N/A'}
      redirect_to "/not_found"
    end
      
  end
    
  def position
    MarketService.position(params: params, user_id: current_user.id)
    
    redirect_to "/stocks/#{params[:symbol]}"
  end
  
  private
  
  def get_data
    
    @marketdata = MarketService.marketdata(symbol: params[:symbol])
    @marketprice = MarketService.marketprice(symbol:params[:symbol])
    
    
    @companydata = MarketService.companydata(symbol: params[:symbol]) 
    @daily = MarketService.dailydata(symbol: params[:symbol])
    
    @record = PositionService.record(symbol: params[:symbol], user_id: current_user.id)
    
    @buyingpower = PositionService.get_buying_power(user_id:current_user.id, balance: current_user.balance, used_margin:current_user.used_margin)
    
    if @companydata[:currency] == 'USD'
      @exchangerate = MarketService.exchange_rate
    else
      @exchangerate = 1.0
    end
    
  end  
  
end  
