class AddSpansToTraces < ActiveRecord::Migration[8.0]
  def change
    add_column :traces, :spans, :json
  end
end
