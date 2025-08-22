class PortfolioRecordWorker
  include Sidekiq::Worker
  
  def perform
    User.find_each(batch_size: 100) do |user|
      today = Date.today
      
      record = PortfolioRecord.find_or_initialize_by(user_id:user.id, date:Date.today)
      record.portfolio_value = PositionService.get_aum(user_id:user.id, balance:user.balance)[:aum]
      record.save!
      
      RedisService.safe_del("portfolio:#{user.id}")  
      
    rescue => e 
      Sentry.capture_exception(e)
    end
  rescue => e
    Sentry.capture_exception(e)
  end
end