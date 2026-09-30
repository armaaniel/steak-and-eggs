module Types
  class PolygonCallsType < Types::BaseObject
    field(:calls, Integer, description: 'polygon rest calls rails made in the range; cache hits never reach polygon', null: false)
    field(:failures, Integer, description: 'calls that raised, a non-200 or a timeout', null: false)
    field(:p50, Float, description: 'median time of a polygon call in ms', null: true)
    field(:p99, Float, description: '99th percentile time of a polygon call in ms', null: true)
    field(:last_success_at, GraphQL::Types::ISO8601DateTime, description: 'the latest call that succeeded, looking back a day', null: true)
  end
end
