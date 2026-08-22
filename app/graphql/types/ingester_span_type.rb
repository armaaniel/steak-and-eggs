module Types
  class IngesterSpanType < Types::BaseObject
    field :at, GraphQL::Types::ISO8601DateTime, null: false
    field :boot_id, String, null: false
    field :connection_id, String, null: true
    field :state, String, null: false
    field :seconds, Float, null: false
  end
end
