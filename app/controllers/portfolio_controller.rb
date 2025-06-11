class PortfolioController < ApplicationController
  
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

  