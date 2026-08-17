# app/graphql/types/synthetic_run_type.rb
module Types
  class SyntheticRunType < Types::BaseObject
    field(:user_id, ID, description: 'the ephemeral user, which identifies the run')
    field(:started_at, GraphQL::Types::ISO8601DateTime)
    field(:request_count, Integer)
    field(:failures, Integer)
    field(:completed, Boolean)
  end
end