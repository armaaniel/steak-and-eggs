module Types
  class IngesterBootType < Types::BaseObject
    field :boot_id, String, null: false
    field :started_at, GraphQL::Types::ISO8601DateTime, null: false
    field :last_seen_at, GraphQL::Types::ISO8601DateTime, null: false
    field :duration_seconds, Float, null: false
    field :connections, Integer, null: false
    field :reconnects, Integer, null: false
    field :clean_exit, Boolean, null: true
    field :events, GraphQL::Types::BigInt, null: true
    field :peak_lag_ms, Integer, null: true
  end
end
