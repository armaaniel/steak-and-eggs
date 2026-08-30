class RemoveMaxLagMsFromIngesterSamples < ActiveRecord::Migration[8.0]
  def change
    remove_column :ingester_samples, :max_lag_ms, :integer
  end
end
