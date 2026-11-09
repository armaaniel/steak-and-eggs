module Types
  class SpanType < Types::BaseObject
    field :name, String, null: false
    field :category, String, null: false
    field :start, Float, null: false
    field :duration, Float, null: false
    field :parent, Integer, null: true
    field :sql, String, null: true
    field :cached, Boolean, null: true
    field :hit, Boolean, null: true
    field :dropped, Integer, null: true
  end
end
