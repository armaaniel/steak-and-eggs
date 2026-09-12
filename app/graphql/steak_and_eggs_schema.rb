# frozen_string_literal: true

class SteakAndEggsSchema < GraphQL::Schema
  query(Types::QueryType)

  # GraphQL-Ruby calls this when a null: false field returns nil:
  def self.type_error(err, context)
    Sentry.capture_exception(err, extra: {
      operation: context.query.operation_name,
      path: context[:current_path]
    })
    super
  end
  
  # Limit the size of incoming queries:
  max_query_string_tokens(5000)

  # Stop validating when it encounters this many errors:
  validate_max_errors(100)

end
