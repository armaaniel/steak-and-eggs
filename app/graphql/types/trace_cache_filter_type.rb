module Types
  class TraceCacheFilterType < GraphQL::Schema::Enum
    description('which traces to keep by how they were served: any call that hit Redis, or any call that went to the database or an API')

    value('CACHED', value: 'cached')
    value('UNCACHED', value: 'uncached')
  end
end
