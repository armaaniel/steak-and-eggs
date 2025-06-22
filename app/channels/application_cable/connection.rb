module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by(:current_user)

    def connect
      self.current_user = find_verified_user
      REDIS.sadd("connected_users", current_user.id)
    end

    def disconnect
      REDIS.srem("connected_users", current_user.id)
    end

    private
      def find_verified_user
        if request.session[:user_id]
          User.find_by(id: request.session[:user_id])
        else
          reject_unauthorized_connection
        end
      end
  end
end