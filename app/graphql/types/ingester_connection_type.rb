module Types
  class IngesterConnectionType < Types::BaseObject
    field :connection_id, String, null: false
    field :boot_id, String, null: false
    field :spawned_at, GraphQL::Types::ISO8601DateTime, null: false
    field :first_message_at, GraphQL::Types::ISO8601DateTime, null: true
    field :last_seen_at, GraphQL::Types::ISO8601DateTime, null: false
    field :ended_at, GraphQL::Types::ISO8601DateTime, null: true
    field :ended_by, String, null: false
    field :duration_seconds, Float, null: true
    field :events, GraphQL::Types::BigInt, null: true
    field :p99_mean_excess_ms, Integer, null: true
  end
end
