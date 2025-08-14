class Ticker < ApplicationRecord
  
  def self.search(term:)
    return [] if term.blank?
    
    payload = {term: term, used_redis: false, used_db: false}
    
    ActiveSupport::Notifications.instrument('Ticker.search', payload) do
      
      cached = RedisService.safe_get("search:#{term}")
    
      if cached
        payload[:used_redis] = true
        return cached
      end
    
      payload[:used_db] = true
    
      results = Ticker.where("symbol ILIKE ? OR name ILIKE ?", "#{term}%", "#{term}%").limit(15)
      RedisService.safe_setex("search:#{term}", 3.days.to_i, results.to_json)
    
      results

    end
    
  rescue => e
    Sentry.capture_exception(e)
    []
  end
  
  def self.query(symbol:)
    return {success:false} if symbol.blank?
    
    cached = RedisService.safe_get("ticker:#{symbol}")
    return {success: true, data: cached} if cached
    
    result = Ticker.find_by(symbol: symbol)
    
    if result
      data = {ticker_type:result.ticker_type, name: result.name, exchange:result.exchange}
      RedisService.safe_setex("ticker:#{symbol}", 1.month.to_i, data.to_json)
      return {success:true, data: data}
    end
    
    {success:false}
  rescue => e
    Sentry.capture_exception(e)
    {success:false}
  end
  
  validates(:symbol, :name, :ticker_type, :exchange, :currency, presence: true)
  validates(:symbol, uniqueness: { case_sensitive: false })  
end
