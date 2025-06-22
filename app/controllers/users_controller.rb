class UsersController < ApplicationController
  def signup
        
    user = UserService.signup(params)
    puts "User created: #{user.inspect}"
    
    if user
      session[:user_id] = user.id
      redirect_to home_path
      puts "Session set: #{session[:user_id]}"
      
    else
      redirect_to login_path
    end
    
  end
  
  def login
        
    user = UserService.authenticate(params)
      
    if user 
      session[:user_id] = user.id
      redirect_to home_path
    else
      redirect_to login_path
    end
    
  end  
      
  def logout
    reset_session
    redirect_to root_path
  end
  
  def update_balance
    UserService.update_balance(amount: params[:amount], user_id: current_user.id, action: params[:commit])    
    redirect_to home_path
  end  
        
    
end
