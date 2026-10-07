module Types
  class TraceSortType < GraphQL::Schema::Enum
    description('the column a trace list is ordered by')

    value('CREATED_AT', value: 'created_at')
    value('DURATION', value: 'duration')
    value('STATUS', value: 'status')
  end
end
