module Types
  class TraceBreakdownType < Types::BaseObject
    field(:redis_query, [Types::TraceType])
    field(:db_api_query, [Types::TraceType])
  end
end
