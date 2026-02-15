class ChangePositionsTransactionsNullColumns < ActiveRecord::Migration[8.0]
  def change
    change_column_null(:positions, :symbol, false)
    change_column_null(:positions, :shares, false)
    change_column_null(:positions, :user_id, false)
    change_column_null(:transactions, :transaction_type, false)
    change_column_null(:transactions, :amount, false)
    change_column_null(:transactions, :quantity, false)
    change_column_null(:transactions, :symbol, false)
  end
end
