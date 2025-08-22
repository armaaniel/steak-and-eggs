class AddPrecisionToColumns < ActiveRecord::Migration[8.0]
  def change
    change_column :positions, :average_price, :decimal, precision: 10, scale: 4
    change_column :transactions, :value, :decimal, precision: 15, scale: 4
    change_column :transactions, :realized_pnl, :decimal, precision: 15, scale: 4
    change_column :transactions, :market_price, :decimal, precision: 10, scale: 4
    change_column :users, :balance, :decimal, precision: 15, scale: 4    
    change_column :portfolio_records, :portfolio_value, :decimal, precision: 15, scale: 4
  end
end