module Types
  class ResourcePointType < Types::BaseObject
    field(:at, GraphQL::Types::ISO8601DateTime, null: false)
    field(:cpu, Float, description: 'highest cpu utilization in the bucket, percent', null: true)
    field(:memory, Float, description: 'highest memory utilization in the bucket, percent', null: true)
  end
end
