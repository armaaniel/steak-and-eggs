class PortfolioController < ApplicationController
  
  def aum
    aum = PositionService.get_aum(user_id: current_user.id, balance: current_user.balance)
    
    render(json: aum)
  end
end

  