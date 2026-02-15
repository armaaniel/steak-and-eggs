module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by(:user)

    def connect
      token = request.params[:token]
      reject_unauthorized_connection unless token

      decoded = JWT.decode(token, Rails.application.secret_key_base, true, algorithm: 'HS256')
      user_id = decoded[0]['user_id']

      self.user = User.find(user_id)

    rescue => e
      Sentry.capture_exception(e)
      reject_unauthorized_connection
    end

    def disconnect
    rescue => e
      Sentry.capture_exception(e)
    end
  end
end
