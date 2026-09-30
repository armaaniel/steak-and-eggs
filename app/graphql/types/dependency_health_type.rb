module Types
  class DependencyHealthType < Types::BaseObject
    field(:id, String, null: false)
    field(:configured, Boolean, description: 'false when the resource id is not set in the environment', null: false)
    field(:status, String, description: 'good, warn, critical or none', null: false)
    field(:readings, [Types::DependencyReadingType], null: false)
  end
end
