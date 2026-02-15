class AddSymbolToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column(:transactions, :symbol, :integer)
  end
end
