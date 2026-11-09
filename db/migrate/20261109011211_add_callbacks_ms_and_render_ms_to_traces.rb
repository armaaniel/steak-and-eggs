class AddCallbacksMsAndRenderMsToTraces < ActiveRecord::Migration[8.0]
  def change
    add_column :traces, :callbacks_ms, :float
    add_column :traces, :render_ms, :float
  end
end
