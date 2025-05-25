module Types
  class PositionsType < Types::BaseObject
    field(:symbol, String)
    field(:shares, Integer)
    field(:user_id, ID)
  end
end
