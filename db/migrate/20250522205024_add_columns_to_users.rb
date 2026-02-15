class AddColumnsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column(:users, :first_name, :string)
    add_column(:users, :last_name, :string)
    add_column(:users, :date_of_birth, :date)
    add_column(:users, :gender, :integer)
    remove_column(:users, :name)
    add_index(:users, :email, unique: true)
    change_column_null(:users, :email, false)
    change_column_null(:users, :password_digest, false)
  end
end
