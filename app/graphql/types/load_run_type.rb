module Types
  class LoadRunType < Types::BaseObject
    field(:run_id, ID, null: false, description: 'identifies the run')
    field(:route, String, null: false)
    field(:started_at, GraphQL::Types::ISO8601DateTime, null: false)
    field(:ended_at, GraphQL::Types::ISO8601DateTime, null: false)
    field(:samples, Integer, null: false, description: 'rows the generator reported for this run and route')
  end
end
