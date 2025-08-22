class IncreasePrecision < ActiveRecord::Migration[8.0]
 def change
   change_column :users, :balance, :decimal, precision: 17, scale: 4
   change_column :portfolio_records, :portfolio_value, :decimal, precision: 17, scale: 4
   change_column :transactions, :value, :decimal, precision: 17, scale: 4
   change_column :transactions, :realized_pnl, :decimal, precision: 17, scale: 4
 end
end