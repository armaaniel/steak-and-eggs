class ApiController < ActionController::API
  
  def verify_token
    
    token = request.headers['authToken']
    return render(json: {error: 'No Token'}, status: 401) unless token
    
    decoded = JWT.decode(token, Rails.application.secret_key_base, true, algorithm: 'HS256')
    user_id = decoded[0]['user_id']
    
    @current_user = Rails.cache.fetch("user_#{user_id}", expires_in: 24.hours) do
      User.find(user_id)
    end
                
  rescue => e
    Sentry.capture_exception(e)
    render(json: {error: 'Authentication failed'}, status: 401)
  end
  
  
end