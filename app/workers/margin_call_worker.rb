class MarginCallWorker 
  include Sidekiq::Worker
  
  def perform
    User.find_each(batch_size: 100) do |user|
      equity_ratio = PositionService.get_buying_power(user_id:user.id,balance:user.balance,used_margin:user.used_margin)[:equity_ratio]
      if equity_ratio < 25
        user.update!(margin_call_status:'active')
      else
        user.update!(margin_call_status:'inactive')
      end
    end
  end
    
  
end