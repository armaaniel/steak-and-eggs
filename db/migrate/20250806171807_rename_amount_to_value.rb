class RenameAmountToValue < ActiveRecord::Migration[8.0]
  def change
    rename_column(:transactions, :amount, :value)
  end
end
