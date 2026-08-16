class ApplicationController < ActionController::API
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

  private

  def synthetic?
    key = ENV['SYNTHETIC_KEY']
    return false if key.blank?
    ActiveSupport::SecurityUtils.secure_compare(request.headers['Synthetic-Key'].to_s, key)
  end

  def append_info_to_payload(payload)
    super
    payload[:user_id] = @current_user&.id
    payload[:synthetic] = synthetic?

  rescue => e
    Sentry.capture_exception(e)
  end

end
