class AddMarginToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column(:users, :used_margin, :decimal)
  end
end
