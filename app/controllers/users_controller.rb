class UsersController < ApplicationController
  def signup
        
    user = User.create(email: params[:email], password: params[:password], first_name: params[:firstName]&.strip&.titleize, 
    middle_name: params[:middleName].presence&.strip&.titleize, last_name: params[:lastName]&.strip&.titleize,
    gender: params[:gender], date_of_birth:params[:dateOfBirth] )
    
    session[:user_id] = user.id
    
    redirect_to home_path
  end
  
  def login
        
    user = User.find_by(email: params[:email])
      
    if user && user.authenticate(params[:password])
      session[:user_id] = user.id
      redirect_to home_path
    else
      redirect_to login_path
    end
    
  end
  
  def update_balance    
    
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
    redirect_to home_path
  end    
      
  def logout
    reset_session
    redirect_to root_path
  end
    
    
    
end
