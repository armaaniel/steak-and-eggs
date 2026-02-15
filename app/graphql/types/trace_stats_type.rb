module Types
 class TraceStatsType < Types::BaseObject
   field(:p50, Float)
   field(:p95, Float)
   field(:p99, Float)
   field(:total_requests, Integer)
   field(:error_rate, Float)
 end
end
