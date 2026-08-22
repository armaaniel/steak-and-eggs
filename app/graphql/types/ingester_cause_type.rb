module Types
  class IngesterCauseType < Types::BaseObject
    field :cause, String, null: false
    field :count, Integer, null: false
  end
end
