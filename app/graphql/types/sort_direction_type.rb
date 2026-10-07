module Types
  class SortDirectionType < GraphQL::Schema::Enum
    value('ASC', value: 'asc')
    value('DESC', value: 'desc')
  end
end
