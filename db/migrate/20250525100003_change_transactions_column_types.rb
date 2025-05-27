class ChangeTransactionsColumnTypes < ActiveRecord::Migration[8.0]
  def change
    change_column(:transactions, :symbol, :string)
    change_column(:transactions, :transaction_type, :integer)
  end
end
