class AddMarginCallStatusToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column(:users, :margin_call_status, :string)
  end
end
