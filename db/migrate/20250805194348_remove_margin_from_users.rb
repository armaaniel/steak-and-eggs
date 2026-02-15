class RemoveMarginFromUsers < ActiveRecord::Migration[8.0]
  def change
    remove_column(:users, :used_margin, :decimal)
    remove_column(:users, :margin_call_status, :string)
  end
end
