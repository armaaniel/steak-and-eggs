class AddUserIdToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_reference :transactions, :user, foreign_key: true, null: false
  end
end
