class PositionsController < ApplicationController
  before_action(:authenticate_user)
  
  def get_position
    position = PositionService.find_position(symbol:params[:symbol], user_id:current_user.id)
    render json: position
  end
  
  def aum
    aum = PositionService.get_aum(user_id: current_user.id, balance: current_user.balance)
    
    render(json: aum)
  end
  
  def buying_power_margin
    
    data = PositionService.get_buying_power(user_id:current_user.id, balance: current_user.balance, 
    used_margin: current_user.used_margin)
    
    render(json: data)
    
  end
    
end

  