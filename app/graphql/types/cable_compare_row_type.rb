module Types
  class CableCompareRowType < Types::BaseObject
    field :at, GraphQL::Types::ISO8601DateTime, null: false
    field :published, Integer, null: true
    field :received, Integer, null: true
    field :clients, Integer, null: true
    field :expected, Integer, null: true
    field :mean_lag_ms, Float, null: true
    field :p99_lag_ms, Float, null: true
    field :peak_clients, Integer, null: true
  end
end
