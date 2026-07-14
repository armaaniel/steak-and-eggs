class RemoveNameFromPositions < ActiveRecord::Migration[8.0]
  def change
    remove_column :positions, :name, :string
  end
end
