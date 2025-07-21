class Ticker < ApplicationRecord
  
  def self.search(term:)
    return [] if term.blank?
    
    payload = {term: term, used_redis: false, used_db: false}
    
    ActiveSupport::Notifications.instrument('Ticker.search', payload) do
      
      cached = RedisService.safe_get("search:#{term}")
    
      if cached
        payload[:used_redis] = true
        return JSON.parse(cached, symbolize_names: true)
      end
    
      payload[:used_db] = true
    
      results = Ticker.where("symbol ILIKE ? OR name ILIKE ?", "#{term}%", "#{term}%")
      RedisService.safe_setex("search:#{term}", 1.hour.to_i, results.to_json)
    
      results

    end
    
  rescue => e
    Sentry.capture_exception(e)
    []
  end

  
  validates(:symbol, :name, :ticker_type, :exchange, :currency, presence: true)
  validates(:symbol, uniqueness: { case_sensitive: false })  
end
