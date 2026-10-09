class AddErrorFieldsToTraces < ActiveRecord::Migration[8.0]
  def change
    add_column :traces, :error_class, :string
    add_column :traces, :error_location, :string
    add_column :traces, :sentry_event_id, :string
  end
end
