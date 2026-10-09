module Types
 class TraceType < Types::BaseObject
   field(:id, ID)
   field(:endpoint, String)
   field(:duration, Float)
   field(:db_runtime, Float)
   field(:status, Integer)
   field(:controller, String)
   field(:action, String)
   field(:breakdown, GraphQL::Types::JSON)
   field(:error_class, String)
   field(:error_location, String)
   field(:sentry_event_id, String)
   field(:created_at, GraphQL::Types::ISO8601DateTime)
   field(:updated_at, GraphQL::Types::ISO8601DateTime)
 end
end
