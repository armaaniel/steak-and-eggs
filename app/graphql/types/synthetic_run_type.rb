# app/graphql/types/synthetic_run_type.rb
module Types
  class SyntheticRunType < Types::BaseObject
    field(:run_id, ID, description: 'identifies the run')
    field(:started_at, GraphQL::Types::ISO8601DateTime)
    field(:request_count, Integer)
    field(:failures, Integer)
    field(:result, String, description: "pass, fail, or null when the run never reported")
  end
end