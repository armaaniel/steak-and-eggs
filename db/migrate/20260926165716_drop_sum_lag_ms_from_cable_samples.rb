class DropSumLagMsFromCableSamples < ActiveRecord::Migration[8.0]
  def change
    remove_column :cable_samples, :sum_lag_ms, :bigint
  end
end
