class UserService
  def self.signup(username:, password:)
    ActiveSupport::Notifications.instrument("UserService.signup.datacat") do
      ActiveRecord::Base.transaction do
        user = User.create!(username: username, password: password)
        PortfolioRecord.create!(date:Date.current, portfolio_value:0, user_id:user.id)

        user
      end
    end
  end

  def self.authenticate(username:, password:)
    ActiveSupport::Notifications.instrument("UserService.authenticate.datacat") do
      User.find_by(username: username&.downcase&.strip)&.authenticate(password)
    end
  end

  def self.deposit(amount:, user_id:)
    ActiveSupport::Notifications.instrument("UserService.deposit.datacat") do
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
      CacheService.invalidate_user(user_id: user_id)
    end
  end

  def self.withdraw(amount:, user_id:)
    ActiveSupport::Notifications.instrument("UserService.withdraw.datacat") do
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
      CacheService.invalidate_user(user_id: user_id)
    end
  end
  
  def self.change_password(user_id:, new_password:)
    ActiveSupport::Notifications.instrument("UserService.change_password.datacat") do
      user = User.find(user_id)
      user.update!(password: new_password)
    end
  end
  
  def self.delete_account(user_id:)
    ActiveSupport::Notifications.instrument("UserService.delete_account.datacat") do
      ActiveRecord::Base.transaction do
        user = User.find(user_id)
        user.destroy!
      end
      CacheService.invalidate_user(user_id: user_id)
    end
  end
end