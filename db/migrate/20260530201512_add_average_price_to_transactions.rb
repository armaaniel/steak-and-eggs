class AddAveragePriceToTransactions < ActiveRecord::Migration[8.0]
    def change
        add_column(:transactions, :average_price, :decimal, precision: 10, scale: 4)
    end
end