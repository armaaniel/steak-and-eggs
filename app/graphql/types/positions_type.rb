module Types
  class PositionsType < Types::BaseObject
    field(:symbol, String)
    field(:shares, Integer)
    field(:user_id, ID)
    field(:current_price, Float)
    
    def current_price
      REDIS.get(object.symbol).to_f.round(2)
    end
    
  end
end
