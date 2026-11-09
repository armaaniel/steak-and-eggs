class AddAppMsToTraces < ActiveRecord::Migration[8.0]
  def change
    add_column :traces, :app_ms, :float
  end
end
