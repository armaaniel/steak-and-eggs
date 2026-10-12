class AddCanaryCoveringIndexToTraces < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX = 'index_traces_on_created_at_canary'

  def up
    remove_index(:traces, name: INDEX, algorithm: :concurrently, if_exists: true)
    add_index(:traces, :created_at, name: INDEX, include: [:run_id, :result, :status], where: "source = 'canary'", algorithm: :concurrently)
    execute("ALTER TABLE traces SET (autovacuum_vacuum_insert_scale_factor = 0.01, autovacuum_vacuum_scale_factor = 0.02)")
  end

  def down
    execute("ALTER TABLE traces RESET (autovacuum_vacuum_insert_scale_factor, autovacuum_vacuum_scale_factor)")
    remove_index(:traces, name: INDEX, algorithm: :concurrently, if_exists: true)
  end
end
