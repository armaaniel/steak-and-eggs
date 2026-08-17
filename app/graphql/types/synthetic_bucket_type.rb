# app/graphql/types/synthetic_bucket_type.rb
module Types
  class SyntheticBucketType < Types::BaseObject
    field(:bucket, GraphQL::Types::ISO8601DateTime, null: false)
    field(:started, Integer, description: 'probe runs that began in this bucket', null: false)
    field(:completed, Integer, description: 'probe runs that reached teardown', null: false)
    field(:failures, Integer, description: '5xx responses in this bucket', null: false)
    field(:expected, Integer, description: 'runs this bucket should contain', null: false)
  end
end