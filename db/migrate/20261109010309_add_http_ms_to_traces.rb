class AddHttpMsToTraces < ActiveRecord::Migration[8.0]
  def change
    add_column :traces, :http_ms, :float
  end
end
