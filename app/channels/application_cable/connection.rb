module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by(:user)

    def connect
      token = request.params[:token]
      reject_unauthorized_connection unless token
      
      decoded = JWT.decode(token, Rails.application.secret_key_base, true, algorithm: 'HS256')
      user_id = decoded[0]['user_id']
      
      self.user = User.find(user_id)  
      
      count = REDIS.incr("user_connections:#{user.id}")
      
      REDIS.sadd("connected_users", user.id) if count == 1
      
    rescue => e
      Sentry.capture_exception(e)
      reject_unauthorized_connection 
    end

    def disconnect
      count = REDIS.decr("user_connections:#{user.id}")
      
      if count <= 0
        REDIS.del("user_connections:#{user.id}")
        REDIS.srem("connected_users", user.id)
      end
      
    rescue => e
      Sentry.capture_exception(e) 
    end
    
  end
end