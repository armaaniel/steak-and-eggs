module Types
  class TraceStatusType < Types::BaseObject
    field(:status, Integer)
    field(:total_requests, Integer)
  end
end
