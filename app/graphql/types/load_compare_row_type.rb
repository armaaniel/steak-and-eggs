module Types
  class LoadCompareRowType < Types::BaseObject
    field(:bucket, GraphQL::Types::ISO8601DateTime, null: false)
    field(:rps, Float, null: false)
    field(:sent, Integer, null: false, description: 'requests the generator counted')
    field(:traced, Integer, null: false, description: 'those that matched a trace by request_id')
    field(:gap, Integer, null: false, description: 'sent that never produced a trace')
    field(:errors, Integer, null: false)
    field(:client_p50, Float, null: false)
    field(:client_p99, Float, null: false)
    field(:server_p50, Float, null: false)
    field(:server_p99, Float, null: false)
    field(:queue_p99, Float, null: false, description: 'client p99 minus server p99')
  end
end
