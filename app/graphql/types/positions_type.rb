module Types
  class PositionsType < Types::BaseObject
    field(:symbol, String)
    field(:shares, Integer)
    field(:user_id, ID)
    field(:current_price, Float)
    field(:name, String)
    
    def current_price
      REDIS.get("price:#{object.symbol}")&.to_f&.round(2)
    rescue => e
      Sentry.capture_exception(e)
      nil
    end
    
  end
end
