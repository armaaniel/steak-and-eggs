class AddNameToPositions < ActiveRecord::Migration[8.0]
  def change
    add_column(:positions, :name, :string)
  end
end
