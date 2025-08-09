class AddAveragePriceToPositions < ActiveRecord::Migration[8.0]
  def change
    add_column(:positions, :average_price, :decimal)
  end
end
