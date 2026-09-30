module Types
  class ServiceBucketType < Types::BaseObject
    field(:bucket, GraphQL::Types::ISO8601DateTime, null: false)
    field(:requests, Integer, null: false)
    field(:errors, Integer, description: '5xx responses in this bucket', null: false)
    field(:p50, Float, description: 'null when the bucket has no requests', null: true)
    field(:p95, Float, null: true)
    field(:p99, Float, null: true)
  end
end
