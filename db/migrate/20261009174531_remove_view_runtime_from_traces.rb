class RemoveViewRuntimeFromTraces < ActiveRecord::Migration[8.0]
  def change
    remove_column :traces, :view_runtime, :float
  end
end
