module Types
  class CacheSplitType < Types::BaseObject
    field(:cached, [Types::TraceType])
    field(:uncached, [Types::TraceType])
  end
end
