class ChangeUsernameIndex < ActiveRecord::Migration[8.0]
  def change
    remove_index(:users, :username)
    add_index(:users, "LOWER(username)", unique: true)
  end
end