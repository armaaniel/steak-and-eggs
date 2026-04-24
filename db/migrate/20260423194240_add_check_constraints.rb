class AddCheckConstraints < ActiveRecord::Migration[8.0]
  def change
    add_check_constraint :users, "balance >= 0", name: "balance_non_negative"

    add_check_constraint :positions, "shares > 0", name: "shares_positive"
    add_check_constraint :positions, "average_price > 0", name: "average_price_positive"

    add_check_constraint :transactions, "quantity > 0", name: "quantity_positive"
    add_check_constraint :transactions, "value > 0", name: "value_positive"
    add_check_constraint :transactions, "market_price >= 0", name: "market_price_non_negative"
    add_check_constraint :transactions, "transaction_type IN (0, 1, 2, 3)", name: "valid_transaction_type"

    add_check_constraint :portfolio_records, "portfolio_value >= 0", name: "portfolio_value_non_negative"
  end
end