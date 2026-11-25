class AddUserCanaryCoveringIndexToTraces < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX = 'index_traces_on_created_at_user_canary'

  def up
    remove_index(:traces, name: INDEX, algorithm: :concurrently, if_exists: true)
    add_index(:traces, :created_at, name: INDEX, include: [:endpoint, :duration, :status, :cache_hits, :cache_misses, :http_ms, :id], where: "source IN ('user', 'canary')", algorithm: :concurrently)
  end

  def down
    remove_index(:traces, name: INDEX, algorithm: :concurrently, if_exists: true)
  end
end
