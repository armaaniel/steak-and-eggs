module Types
  class RunMetricType < Types::BaseObject
    field(:at, GraphQL::Types::ISO8601DateTime, null: false)
    field(:minimum, Float)
    field(:maximum, Float)
    field(:average, Float)
  end
end
