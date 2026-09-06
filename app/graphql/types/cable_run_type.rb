module Types
  class CableRunType < Types::BaseObject
    field :run_id, ID, null: false
    field :started_at, GraphQL::Types::ISO8601DateTime, null: false
    field :ended_at, GraphQL::Types::ISO8601DateTime, null: false
    field :samples, Integer, null: false
  end
end
