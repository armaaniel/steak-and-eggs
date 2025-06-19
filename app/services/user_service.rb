class UserService 
  def self.signup(params)
    User.transaction do
      User.create!(email: params[:email], password: params[:password], first_name: params[:firstName]&.strip&.titleize,
      middle_name: params[:middleName]&.strip&.titleize, last_name: params[:lastName]&.strip&.titleize, gender: params[:gender],
      date_of_birth: params[:dateOfBirth])
    
      PortfolioRecord.create!(date:Date.today, portfolio_value:0, user_id:user.id)
    end
    
  rescue => e
    Sentry.capture_exception(e)
    nil    
  end
  
  def self.authenticate(params)
    user = User.find_by(email: params[:email])&.authenticate(params[:password])
  end
  
  def self.update_balance(params:, current_user:)
    case params[:commit] 
    when 'add'
      Transaction.transaction do
        Transaction.create!(symbol:'CAD', quantity: 1, amount: params[:amount].to_f, transaction_type: 'Deposit', user_id: current_user.id)
        current_user.balance += params[:amount].to_f
        current_user.save!
      end
    when 'withdraw'
      Transaction.transaction do
        Transaction.create!(symbol: 'CAD', quantity: 1, amount: params[:amount].to_f, transaction_type: 'Withdraw', user_id: current_user.id)
        current_user.balance -= params[:amount].to_f
        current_user.save!
      end
    end
  rescue => e
    Sentry.capture_exception(e)
    nil
  end
end
      