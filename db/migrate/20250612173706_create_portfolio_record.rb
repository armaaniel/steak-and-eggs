class CreatePortfolioRecord < ActiveRecord::Migration[8.0]
  def change
    create_table(:portfolio_records) do |n|
      n.references(:user, null: false, foreign_key: true)
      n.date(:date, null:false)
      n.decimal(:portfolio_value)
      n.index([:user_id, :date], unique: true)
    end
  end
end
