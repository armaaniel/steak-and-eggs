class UserService   
  def self.signup(username:, password:)
    
    ActiveRecord::Base.transaction do
      user = User.create!(username: username, password: password)
      PortfolioRecord.create!(date:Date.current, portfolio_value:0, user_id:user.id)
      
      user
    end
  end
  
  def self.authenticate(username:, password:)  
    User.find_by(username: username)&.authenticate(password)
  end
  
  def self.deposit(amount:, user_id:)
    raise ArgumentError if amount.nil? || amount&.to_f <= 0  
    amount = amount.to_f
    
    ActiveSupport::Notifications.instrument("UserService.deposit") do
      
      ActiveRecord::Base.transaction do
        user = User.lock.find(user_id)
      
        user.balance += amount
        user.save!
      
        Transaction.create!(symbol:'USD', quantity: 1, value: amount, transaction_type: 'Deposit', user_id: user_id, 
        market_price: 1.00)
            
        record = PortfolioRecord.find_or_initialize_by(user_id:user_id, date:Date.current)
      
        record.portfolio_value = PositionService.get_aum(user_id:user_id, balance:user.balance)[:aum]
        record.save!      
      end   
      RedisService.safe_del("portfolio:#{user_id}")  
      RedisService.safe_del("activity:#{user_id}")   
    end   
  end
  
  def self.withdraw(amount:, user_id:)
    raise ArgumentError if amount.nil? || amount&.to_f <= 0
    amount = amount.to_f
    
    ActiveSupport::Notifications.instrument("UserService.withdraw") do
      
      ActiveRecord::Base.transaction do
        user = User.lock.find(user_id)
      
        raise StandardError if user.balance < amount
        user.balance -= amount
        user.save!
      
        Transaction.create!(symbol:'USD', quantity: 1, value: amount, transaction_type:'Withdraw', user_id:user_id, 
        market_price: 1.00)
      
        record = PortfolioRecord.find_or_initialize_by(user_id:user_id, date:Date.current)
      
        record.portfolio_value = PositionService.get_aum(user_id:user_id, balance:user.balance)[:aum]
        record.save!
      end  
      RedisService.safe_del("portfolio:#{user_id}")
      RedisService.safe_del("activity:#{user_id}")
    end 
  end
  
end
      