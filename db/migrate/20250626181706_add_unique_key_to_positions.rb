class AddUniqueKeyToPositions < ActiveRecord::Migration[8.0]
  def change
    add_index(:positions, [:user_id, :symbol], unique: true)
  end
end