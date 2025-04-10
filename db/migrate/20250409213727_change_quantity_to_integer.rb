class ChangeQuantityToInteger < ActiveRecord::Migration[8.0]
  def change
    change_column(:transactions, :quantity, :integer)
  end
end
