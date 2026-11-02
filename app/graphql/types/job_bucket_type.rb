module Types
  class JobBucketType < Types::BaseObject
    field(:name, String, description: 'the rake task, as scheduled in main.tf', null: false)
    field(:bucket, GraphQL::Types::ISO8601DateTime, description: 'start of the utc day', null: false)
    field(:bucket_end, GraphQL::Types::ISO8601DateTime, description: 'exclusive upper bound of this bucket', null: false)
    field(:started, Integer, description: 'runs that began this day', null: false)
    field(:completed, Integer, description: 'runs that finished without an error', null: false)
    field(:failures, Integer, description: 'runs that raised, or never finished within an hour', null: false)
    field(:expected, Integer, description: '1 once the scheduled hour plus an hour of grace has passed', null: false)
  end
end
