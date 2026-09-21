class AddProcessAndIdleTimingToIngesterSamples < ActiveRecord::Migration[8.0]
  def change
    add_column :ingester_samples, :sum_process_ms, :bigint
    add_column :ingester_samples, :sum_idle_ms, :bigint
  end
end