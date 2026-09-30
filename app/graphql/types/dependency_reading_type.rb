module Types
  class DependencyReadingType < Types::BaseObject
    field(:key, String, null: false)
    field(:label, String, null: false)
    field(:unit, String, description: 'percent, count or bytes', null: false)
    field(:now, Float, description: 'latest one-minute value in the last hour', null: true)
    field(:peak, Float, description: 'highest one-minute value in the last hour', null: true)
    field(:total, Float, description: 'sum over the last hour, for counters only', null: true)
    field(:points, [Types::DependencyPointType], description: 'one-minute values over the last hour, for percentages only', null: false)
  end
end
