class CreateTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table(:transactions) do |n|
      n.string(:transaction_type)
      n.decimal(:amount)
      n.decimal(:quantity)
      n.timestamps
    end
  end
end
