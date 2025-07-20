class StocksController < ApplicationController
  before_action(:authenticate_user)
  layout 'authenticated'
  def show
        
    if Ticker.find_by(symbol:params[:symbol]).nil?
      return redirect_to "/not_found"
    end 
    
    @marketprice = MarketService.marketprice(symbol:params[:symbol])
    @record = PositionService.find_position(symbol:params[:symbol], user_id:current_user.id)
    @name = PositionService.get_name(symbol:params[:symbol]) 
    @buyingpower = PositionService.get_buying_power(user_id:current_user.id, balance: current_user.balance, used_margin:current_user.used_margin)
    
  end
    
  def position
    MarketService.position(params: params, user_id: current_user.id)
    
    redirect_to "/stocks/#{params[:symbol]}"
  end
  
  def get_market_data
    data = MarketService.marketdata(symbol:params[:symbol])
    render json:data
  end
  
  def get_company_data
    data = MarketService.companydata(symbol:params[:symbol])
    render json:data
  end
  
  def get_chart_data
    data = MarketService.chartdata(symbol:params[:symbol])
    render json:data
  end
  
end  
