class UsersController < ApiController
  before_action(:verify_token, except: [:login, :signup, :connections])
  
  def login
    
    user = UserService.authenticate(username:params[:username],password:params[:password])
        
    if user
      payload = {user_id: user.id, exp: 24.hours.from_now.to_i}
      token = JWT.encode(payload, Rails.application.secret_key_base, 'HS256')
      
      render(json: {token: token})
    else
      render(json: {error: 'Invalid Credentials' }, status: 401) 
    end
    
  end
  
  def signup
    
    user = UserService.signup(username:params[:username], password:params[:password])
    
    if user
      payload = {user_id: user.id, exp: 24.hours.from_now.to_i}
      token = JWT.encode(payload, Rails.application.secret_key_base, 'HS256')
      
      render(json: {token: token})
    else
      render(json: {error: 'Signup failed'}, status: 422)
    end
  end
  
  def connections
      connections_info = ActionCable.server.connections.map do |conn|
        {
          user_id: conn.user&.id,
          started_at: conn.instance_variable_get(:@started_at),
          subscriptions: conn.subscriptions.identifiers
        }
      end
    
      render json: {
        actioncable_connections: connections_info.length,
        details: connections_info,
      }
    end
      
  
  def deposit
    
    result = UserService.deposit(amount:params[:amount], user_id:@current_user.id)
    
    if result[:success]
      head(:ok)
    else
      render(json: {error: 'Unable to process deposit'}, status: 422)
    end
      
  end
  
  def withdraw
    
    result = UserService.withdraw(amount:params[:amount], user_id:@current_user.id)
    
    if result[:success]
      head(:ok)
    else
      render(json: {error: 'Unable to process withdrawal'}, status: 422)
    end
    
  end
   
  
end