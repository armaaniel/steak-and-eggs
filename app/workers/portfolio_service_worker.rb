class PortfolioServiceWorker 
  include Sidekiq::Worker
  
  def perform
    User.find_each(batch_size: 100) do |user|
      today = Date.today
      portfolio = PositionService.get_buying_power(user_id:user.id,balance:user.balance,used_margin:user.used_margin)
      
      unless portfolio
        Sentry.capture_message("Missing portfolio data for user #{user.id}")
        next
      end
      
      equity_ratio = portfolio[:equity_ratio]
      portfolio_value = portfolio[:portfolio_value]
      
      record = PortfolioRecord.find_or_initialize_by(user_id:user_id, date:Date.today)
      record.portfolio_value = PositionService.get_aum(user_id:user_id, balance:user.balance)[:aum]
      record.save!
            
      if equity_ratio < 250
        user.update!(margin_call_status:'active')
      else
        user.update!(margin_call_status:'inactive')
      end
      
    rescue => e 
      Sentry.capture_exception(e)
    end
  end
    
  
end