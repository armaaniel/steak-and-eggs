class PortfolioController < ApplicationController
  before_action(:authenticate_user)
  
  def positions
    positions = PositionService.positions(current_user: current_user)
    render json: positions
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

  