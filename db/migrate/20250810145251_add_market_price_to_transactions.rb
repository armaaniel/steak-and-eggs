class AddMarketPriceToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column(:transactions, :market_price, :decimal, null: false)
  end
end
