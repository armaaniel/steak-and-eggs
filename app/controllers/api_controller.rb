class ApiController < ActionController::API
  
  rescue_from(ArgumentError, with: :bad_request)
  rescue_from(ActiveRecord::RecordNotFound, with: :not_found)
  rescue_from(ActiveRecord::RecordInvalid, with: :validation_error)
  rescue_from(StandardError, with: :service_error)
  
  def verify_token
    
    token = request.headers['authToken']
    return render(json: {error: 'No Token'}, status: 401) unless token
    
    decoded = JWT.decode(token, Rails.application.secret_key_base, true, algorithm: 'HS256')
    user_id = decoded[0]['user_id']
    
    @current_user = Rails.cache.fetch("user_#{user_id}", expires_in: 15.minutes.to_i) do
      User.find(user_id)
    end
                
  rescue => e
    Sentry.capture_exception(e)
    render(json: {error: 'Authentication failed'}, status: 401)
  end
  
  private
  
  def bad_request(e)
    render(json: {error: e.message}, status: 400)
  end
  
  def not_found(e)
    render(json: {error: "Not Found"}, status: 404)
  end
  
  def validation_error(e)
    render(json: {error: e.message}, status: 422)
  end
  
  def service_error(e)
    render(json: {error: "Service temporarily unavailable"}, status: 503)
  end
  
end