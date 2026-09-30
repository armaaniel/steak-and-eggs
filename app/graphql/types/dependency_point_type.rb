module Types
  class DependencyPointType < Types::BaseObject
    field(:at, GraphQL::Types::ISO8601DateTime, null: false)
    field(:value, Float, null: false)
  end
end
