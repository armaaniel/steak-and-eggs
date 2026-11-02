module Types
  class JobRunType < Types::BaseObject
    field(:id, ID, null: false)
    field(:name, String, null: false)
    field(:started_at, GraphQL::Types::ISO8601DateTime, null: false)
    field(:finished_at, GraphQL::Types::ISO8601DateTime)
    field(:error_class, String)
    field(:sentry_event_id, String)
    field(:status, String, description: 'succeeded, failed, or running, worked out from the timestamps', null: false)
  end
end
