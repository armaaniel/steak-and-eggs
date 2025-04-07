class UsersController < ApplicationController
  def create
    
    #maybe circle back to this and use strong parameters, error handling, redirect
    
    params2 = {}
    params2[:email] = params[:email]
    params2[:password] = params[:password]
    
    user = User.create(params2)
    
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
    when 'add funds'
      current_user.balance += params[:amount].to_f
      current_user.save
    when 'withdraw funds'
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
