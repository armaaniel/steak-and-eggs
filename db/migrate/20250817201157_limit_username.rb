class LimitUsername < ActiveRecord::Migration[8.0]
  def change
    change_column(:users, :username, :string, limit:20)
  end
end
