class ApplicationController < ActionController::Base
  skip_before_action :verify_authenticity_token, only: [:record]
  before_action :verify_key, only: [:record]

  def health
    render(json:{status:'ok', time: Time.current}, status:200)
  end

  def not_found
    render(json:{error:'Not Found'}, status: 404)
  rescue => e
    Sentry.capture_exception(e)
    render(json:{error:'Not Found'}, status: 404)
  end

  def record
    User.find_each(batch_size: 100) do |user|
      record = PortfolioRecord.find_or_initialize_by(user_id:user.id, date:Date.current)
      record.portfolio_value = PositionService.get_aum(user_id:user.id, balance:user.balance)[:aum]
      record.save!

      RedisService.safe_del("portfolio:#{user.id}")

    rescue => e
      Sentry.capture_exception(e)
    end

    head(:ok)

  rescue => e
    Sentry.capture_exception(e)
  end

  private

  def verify_key
    render(json:{error: 'Unauthorized'}, status: 401) unless request.headers['Key'] == ENV['GQL_KEY']
  end
end
