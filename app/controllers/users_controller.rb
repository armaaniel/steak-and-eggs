class UsersController < ApplicationController
  skip_before_action :verify_authenticity_token
  
  def login
        
    user = UserService.authenticate(username:params[:username], password:params[:password])
      
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
          
    
end
