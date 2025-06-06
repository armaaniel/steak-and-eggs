class UserService 
  def self.signup(params)
    User.create(email: params[:email], password: params[:password], first_name: params[:firstName]&.strip&.titleize,
    middle_name: params[:middleName]&.strip&.titleize, last_name: params[:lastName]&.strip&.titleize, gender: params[:gender],
    date_of_birth: params[:dateOfBirth])
  end
  
  def self.authenticate(params)
    user = User.find_by(email: params[:email])&.authenticate(params[:password])
  end
  
  def self.update_balance(params:, current_user:)
    case params[:commit] 
    when 'add'
      Transaction.create(symbol:'CAD', quantity: 1, amount: params[:amount].to_f, transaction_type: 'Deposit', user_id: current_user.id)
      current_user.balance += params[:amount].to_f
      current_user.save
    when 'withdraw'
      Transaction.create(symbol: 'CAD', quantity: 1, amount: params[:amount].to_f, transaction_type: 'Withdraw', user_id: current_user.id)
      current_user.balance -= params[:amount].to_f
      current_user.save
    end
  end
end
      