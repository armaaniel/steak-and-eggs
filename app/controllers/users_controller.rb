class UsersController < ApiController
  before_action(:verify_token, except: [:login, :signup])
  
  def login
    overall_start = Time.current
    Rails.logger.info "=== LOGIN REQUEST START ==="
  
    # Time parameter parsing
    parse_start = Time.current
    username = params[:username]
    password = params[:password]
    Rails.logger.info "Parameter parsing: #{(Time.current - parse_start) * 1000}ms"
  
    # Time authentication
    auth_start = Time.current
    user = UserService.authenticate(username: username, password: password)
    auth_time = (Time.current - auth_start) * 1000
    Rails.logger.info "UserService.authenticate: #{auth_time}ms"
      
    if user
      # Time JWT creation
      jwt_start = Time.current
      payload = {user_id: user.id, exp: 24.hours.from_now.to_i}
      token = JWT.encode(payload, Rails.application.secret_key_base, 'HS256')
      jwt_time = (Time.current - jwt_start) * 1000
      Rails.logger.info "JWT creation: #{jwt_time}ms"
    
      # Time JSON rendering
      render_start = Time.current
      render(json: {token: token})
      render_time = (Time.current - render_start) * 1000
      Rails.logger.info "JSON render: #{render_time}ms"
    else
      render(json: {error: 'Your email or password was incorrect. Please try again' }, status: 401) 
    end
  
    total_time = (Time.current - overall_start) * 1000
    Rails.logger.info "=== TOTAL LOGIN TIME: #{total_time}ms ==="
  
  rescue => e
    Rails.logger.error "Login error after #{(Time.current - overall_start) * 1000}ms: #{e.message}"
    render(json: {error: 'Something went wrong, please try again' }, status: 503) 
  end
  
  def signup
    user = UserService.signup(username:params[:username], password:params[:password])
        
    if user
      payload = {user_id: user.id, exp: 24.hours.from_now.to_i}
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