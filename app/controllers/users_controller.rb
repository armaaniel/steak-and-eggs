class UsersController < ApiController
  before_action(:verify_token, except: [:login, :signup])
  
  def login
    user = UserService.authenticate(username: params[:username].downcase, password: params[:password])
      
    if user
      payload = {user_id: user.id}
      token = JWT.encode(payload, Rails.application.secret_key_base, 'HS256')
      render(json: {token: token})
    else
      render(json: {error: 'Your email or password was incorrect. Please try again' }, status: 401) 
    end
  
  rescue => e
    Sentry.capture_exception(e)
    render(json: {error: 'Something went wrong, please try again' }, status: 503) 
  end
  
  def signup
    user = UserService.signup(username:params[:username], password:params[:password])
        
    if user
      payload = {user_id: user.id}
      token = JWT.encode(payload, Rails.application.secret_key_base, 'HS256')
      render(json: {token: token})
    end
    
  rescue ActiveRecord::RecordInvalid => e
    render(json: {error: "Username has been taken, please choose another"}, status: 422)
  rescue => e
    Sentry.capture_exception(e)
    render(json: {error:"Something went wrong, please try again"}, status: 503)  
  end
    
  def deposit
    result = UserService.deposit(amount:params[:amount], user_id:@current_user.id)
    head(:ok)
    
  rescue => e
    Sentry.capture_exception(e)
    render(json: {error: 'Unable to process deposit, please try again'}, status: 422)  
  end
  
  def withdraw
    result = UserService.withdraw(amount:params[:amount], user_id:@current_user.id)
    head(:ok)

  rescue => e
    Sentry.capture_exception(e)
    render(json: {error: 'Unable to process withdrawal, try again'}, status: 422)
  end
  
end