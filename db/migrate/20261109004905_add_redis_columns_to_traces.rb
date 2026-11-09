class AddRedisColumnsToTraces < ActiveRecord::Migration[8.0]
  def change
    add_column :traces, :redis_ms, :float
    add_column :traces, :cache_hits, :integer
    add_column :traces, :cache_misses, :integer
  end
end
