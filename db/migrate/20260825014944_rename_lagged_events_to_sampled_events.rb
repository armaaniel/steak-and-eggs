class RenameLaggedEventsToSampledEvents < ActiveRecord::Migration[8.0]
  def change
    rename_column :ingester_samples, :lagged_events, :sampled_events
  end
end
