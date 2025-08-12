class UserService 
  def self.signup(username:, password:)
    ActiveRecord::Base.transaction do
      user = User.create!(username: username, password: password)
      
      PortfolioRecord.create!(date:Date.today, portfolio_value:0, user_id:user.id)
      user
    end
    
  rescue => e
    Sentry.capture_exception(e)
    nil 
  end
  
  def self.authenticate(username:, password:)
    user = User.find_by(username: username)&.authenticate(password)
  end
  
  def self.deposit(amount:, user_id:)
    return if amount.nil? || amount&.to_f <= 0
    amount = amount.to_f
    
    ActiveRecord::Base.transaction do
      user = User.lock.find(user_id)
      
      user.balance += amount
      user.save!
      
      Transaction.create!(symbol:'USD', quantity: 1, value: amount, transaction_type: 'Deposit', user_id: user_id, 
      market_price: 1.00)
            
      record = PortfolioRecord.find_or_initialize_by(user_id:user_id, date:Date.today)
      
      record.portfolio_value = PositionService.get_aum(user_id:user_id, balance:user.balance)[:aum]
      record.save!      
    end
       
    RedisService.safe_del("portfolio:#{user_id}")
    {success: true} 
     
  rescue => e
    Sentry.capture_exception(e)
    {success: false}
  end
  
  def self.withdraw(amount:, user_id:)
    return if amount.nil? || amount&.to_f <=0
    amount = amount.to_f
    
    ActiveRecord::Base.transaction do
      user = User.lock.find(user_id)
      
      user.balance -= amount
      user.save!
      
      Transaction.create!(symbol:'USD', quantity: 1, value: amount, transaction_type:'Withdraw', user_id:user_id, 
      market_price: 1.00)
      
      record = PortfolioRecord.find_or_initialize_by(user_id:user_id, date:Date.today)
      
      record.portfolio_value = PositionService.get_aum(user_id:user_id, balance:user.balance)[:aum]
      record.save!
    end
    
    RedisService.safe_del("portfolio:#{user_id}")
    {success:true}
    
  rescue => e
    Sentry.capture_exception(e)
    {sucess: false}
    
  end
  
end
      