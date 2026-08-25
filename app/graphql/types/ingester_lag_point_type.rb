module Types
  class IngesterLagPointType < Types::BaseObject
    field :at, GraphQL::Types::ISO8601DateTime, null: false
    field :max_excess_ms, Integer, null: true
    field :mean_excess_ms, Float, null: true
    field :sampled_events, Integer, null: true
    field :symbols, Integer, null: true
  end
end