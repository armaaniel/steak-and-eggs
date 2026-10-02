module Types
  class TraceScatterPointType < Types::BaseObject
    field(:id, ID, description: 'the slowest trace in this cell, so a click opens the worst request', null: false)
    field(:at, GraphQL::Types::ISO8601DateTime, null: false)
    field(:status, Integer, null: true)
    field(:duration, Float, null: false)
    field(:count, Integer, description: 'how many requests landed in this cell', null: false)
  end
end
