class ApplicationController < ActionController::API
  SYNTHETIC_SOURCES = %w[canary load].freeze
  RESULTS = %w[pass fail].freeze
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
    if synthetic?
      payload[:source] = request.headers['Synthetic-Source'].presence_in(SYNTHETIC_SOURCES) || 'unknown'
      payload[:run_id] = request.headers['Synthetic-Run-Id'].presence
      payload[:result] = request.headers['Synthetic-Result'].presence_in(RESULTS)
      payload[:request_id] = request.headers['X-Load-Request-Id'].presence
    else
      payload[:source] = 'user'
    end
  rescue => e
    Sentry.capture_exception(e)
  end

end
