class AddDefaultToMargin < ActiveRecord::Migration[8.0]
  def change
    change_column_default(:users, :used_margin, 0)
    User.where(used_margin: nil).update_all(used_margin: 0)
    change_column_null(:users, :used_margin, false)
  end
end