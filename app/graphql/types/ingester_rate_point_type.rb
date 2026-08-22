module Types
  class IngesterRatePointType < Types::BaseObject
    field :at, GraphQL::Types::ISO8601DateTime, null: false
    field :events_per_sec, Float, null: true
    field :frames_per_sec, Float, null: true
    field :max_lag_ms, Integer, null: true
    field :symbols, Integer, null: true
  end
end
