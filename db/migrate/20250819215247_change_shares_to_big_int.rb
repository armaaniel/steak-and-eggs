class ChangeSharesToBigInt < ActiveRecord::Migration[8.0]
  def change
    change_column :positions, :shares, :bigint
  end
end
