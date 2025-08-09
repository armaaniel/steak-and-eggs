class ChangeNullForAveragePrice < ActiveRecord::Migration[8.0]
  def change
    change_column_null(:positions, :average_price, false)
  end
end
