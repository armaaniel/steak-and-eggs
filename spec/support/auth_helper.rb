module AuthHelper
  def auth_headers(user)
    token = JWT.encode({ user_id: user.id }, Rails.application.secret_key_base, 'HS256')
    { "authToken" => token }
  end
end

RSpec.configure do |config|
  config.include(AuthHelper, type: :request)
end
