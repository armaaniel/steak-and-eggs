class UserService 
  def self.signup(params)
    ActiveRecord::Base.transaction do
      user = User.create!(email: params[:email], password: params[:password], first_name: params[:firstName]&.strip&.titleize,
      middle_name: params[:middleName]&.strip&.titleize, last_name: params[:lastName]&.strip&.titleize, gender: params[:gender],
      date_of_birth: params[:dateOfBirth])
    
      PortfolioRecord.create!(date:Date.today, portfolio_value:0, user_id:user.id)
      user
    end
    
  rescue => e
    Sentry.capture_exception(e)
    nil    
  end
  
  def self.authenticate(params)
    user = User.find_by(email: params[:email])&.authenticate(params[:password])
  end
  
  def self.update_balance(amount:, user_id:, action:)
    return if amount.nil? || amount&.to_f <= 0
    amount = amount.to_f
    
    case action
    when 'add'
      ActiveRecord::Base.transaction do
        user = User.lock.find(user_id)
        
        user.balance += amount
        user.save!
        
        Transaction.create!(symbol:'CAD', quantity: 1, amount: amount, transaction_type: 'Deposit', user_id: user_id)
        
        record = PortfolioRecord.find_or_initialize_by(user_id:user_id, date:Date.today)
        record.portfolio_value = PositionService.get_aum(user_id:user_id, balance:user.balance)[:aum]
        record.save!
      end
    when 'withdraw'
      ActiveRecord::Base.transaction do
        user = User.lock.find(user_id)
        
        return false if user.balance < amount
        
        user.balance -= amount
        user.save!
        
        Transaction.create!(symbol: 'CAD', quantity: 1, amount: amount, transaction_type: 'Withdraw', user_id: user_id)
        record = PortfolioRecord.find_or_initialize_by(user_id:user_id, date:Date.today)
        record.portfolio_value = PositionService.get_aum(user_id:user_id, balance:user.balance)[:aum]
        record.save!
      end
    end
    
    RedisService.safe_del("portfolio:#{user_id}")
    
  rescue => e
    Sentry.capture_exception(e)
    nil
  end
  
  
end
      