class AddNullConstraintToPortfolioValue < ActiveRecord::Migration[8.0]
  def change
    change_column_null(:portfolio_records, :portfolio_value, false)
  end
end
