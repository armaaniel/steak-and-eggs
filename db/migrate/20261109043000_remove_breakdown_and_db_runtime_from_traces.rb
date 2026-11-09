class RemoveBreakdownAndDbRuntimeFromTraces < ActiveRecord::Migration[8.0]
  def change
    remove_column :traces, :breakdown, :json
    remove_column :traces, :db_runtime, :float
  end
end
