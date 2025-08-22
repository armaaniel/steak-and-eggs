module Types
  class TransactionsType < Types::BaseObject
    field(:user_id, ID)
    field(:transaction_type, String)
    field(:value, Float)
    field(:quantity, Integer)
    field(:created_at, String)
    field(:symbol, String)
    field(:id, ID)
  end
end

    