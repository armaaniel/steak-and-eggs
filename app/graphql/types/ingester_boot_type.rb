module Types
  class IngesterBootType < Types::BaseObject
    field :boot_id, String, null: false
    field :started_at, GraphQL::Types::ISO8601DateTime, null: false
    field :last_seen_at, GraphQL::Types::ISO8601DateTime, null: false
    field :duration_seconds, Float, null: false
    field :connections, Integer, null: false
    field :reconnects, Integer, null: false
    field :exit_state, String, null: false
  end
end
