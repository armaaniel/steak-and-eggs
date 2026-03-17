class UserService
  def self.signup(username:, password:)
    ActiveRecord::Base.transaction do
      user = User.create!(username: username, password: password)
      PortfolioRecord.create!(date:Date.current, portfolio_value:0, user_id:user.id)

      user
    end
  end

  def self.authenticate(username:, password:)
    User.find_by(username: username&.downcase&.strip)&.authenticate(password)
  end

  def self.deposit(amount:, user_id:)
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

  def self.delete_account(user_id:, password:)
    user = User.find(user_id)
    raise StandardError unless user.authenticate(password)

    user.destroy!
    Rails.cache.delete("user_#{user_id}")
    RedisService.safe_del("portfolio:#{user_id}")
    RedisService.safe_del("activity:#{user_id}")
  end

  def self.change_password(user_id:, current_password:, new_password:)
    user = User.find(user_id)
    raise StandardError, "Current password is incorrect" unless user.authenticate(current_password)

    user.update!(password: new_password)
  end

  def self.withdraw(amount:, user_id:)
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