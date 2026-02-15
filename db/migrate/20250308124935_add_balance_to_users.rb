class AddBalanceToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column(:users, :balance, :decimal)
  end
end
