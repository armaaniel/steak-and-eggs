module Types
  class IngesterTransitionType < Types::BaseObject
    field :id, ID, null: false
    field :at, GraphQL::Types::ISO8601DateTime, null: false
    field :boot_id, String, null: false
    field :connection_id, String, null: true
    field :state, String, null: false
    field :cause, String, null: true
    field :detail, GraphQL::Types::JSON, null: true
  end
end
