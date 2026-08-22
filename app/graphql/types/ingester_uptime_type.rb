module Types
  class IngesterUptimeType < Types::BaseObject
    field :pct, Float, null: false
    field :streaming_seconds, Float, null: false
    field :idle_seconds, Float, null: false
    field :down_seconds, Float, null: false
    field :unaccounted_seconds, Float, null: false
    field :window_seconds, Float, null: false
  end
end
