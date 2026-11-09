class AddSqlMsToTraces < ActiveRecord::Migration[8.0]
  def change
    add_column :traces, :sql_ms, :float
  end
end
