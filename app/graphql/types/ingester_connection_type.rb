module Types
  class IngesterConnectionType < Types::BaseObject
    field :connection_id, String, null: false
    field :boot_id, String, null: false
    field :spawned_at, GraphQL::Types::ISO8601DateTime, null: false
    field :first_message_at, GraphQL::Types::ISO8601DateTime, null: true
    field :last_seen_at, GraphQL::Types::ISO8601DateTime, null: false
    field :ended_at, GraphQL::Types::ISO8601DateTime, null: true
    field :ended_by, String, null: true
    field :connect_seconds, Float, null: true
    field :duration_seconds, Float, null: true
  end
end
