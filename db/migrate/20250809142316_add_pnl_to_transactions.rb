class AddPnlToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column(:transactions, :realized_pnl, :decimal)
  end
end
