class AddLagStatsToIngesterSamples < ActiveRecord::Migration[8.0]
  def change
    add_column :ingester_samples, :sum_lag_ms, :bigint
    add_column :ingester_samples, :lagged_events, :integer
  end
end