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
   field(:spans, [Types::SpanType]) do
     description('the waterfall, loaded only by trace(id:), since trace lists leave it out')
   end
   field(:app_ms, Float)
   field(:sql_ms, Float)
   field(:redis_ms, Float)
   field(:http_ms, Float)
   field(:callbacks_ms, Float)
   field(:render_ms, Float)
   field(:error_class, String)
   field(:error_location, String)
   field(:sentry_event_id, String)
   field(:created_at, GraphQL::Types::ISO8601DateTime)
   field(:updated_at, GraphQL::Types::ISO8601DateTime)

   def spans
     object.spans if object.has_attribute?(:spans)
   end
 end
end
