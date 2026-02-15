class CreateTickersTable < ActiveRecord::Migration[8.0]
  def change
    create_table(:tickers) do |n|
      n.string(:symbol, null: false)
      n.string(:name, null: false)
      n.string(:ticker_type, null: false)
      n.string(:exchange, null: false)
      n.string(:currency, null: false)

      n.timestamps

      n.index(:symbol, unique: true)
    end
  end
end
