module Types
 class TraceSummaryType < Types::BaseObject
   field(:route, String)
   field(:endpoint, String)
   field(:p99, Float)
   field(:total_requests, Integer)
   field(:clean_route, String)
 end
end
