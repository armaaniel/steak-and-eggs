class UsersController < ApplicationController
  def create
    
    #todo strong parameters, error handling, negative amounts
    
    user = User.create(email: params[:email], password: params[:password])
    
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
      current_user.balance += params[:amount].to_f
      current_user.save
      Transaction.create(quantity: 1, amount: params[:amount].to_f, transaction_type: 'Deposit', user_id: current_user.id)
    when 'withdraw'
      current_user.balance -= params[:amount].to_f
      current_user.save
      Transaction.create(quantity: 1, amount: params[:amount].to_f, transaction_type: 'Withdraw', user_id: current_user.id)
    end
    redirect_to home_path
  end    
      
  def logout
    reset_session
    redirect_to root_path
  end
    
    
    
end
