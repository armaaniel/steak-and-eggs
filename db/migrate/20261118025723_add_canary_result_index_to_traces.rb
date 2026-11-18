class AddCanaryResultIndexToTraces < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX = 'index_traces_on_created_at_canary_result'

  def up
    remove_index(:traces, name: INDEX, algorithm: :concurrently, if_exists: true)
    add_index(:traces, :created_at, name: INDEX, include: [:run_id, :result, :status], where: "source = 'canary' AND result IS NOT NULL", algorithm: :concurrently)
  end

  def down
    remove_index(:traces, name: INDEX, algorithm: :concurrently, if_exists: true)
  end
end
