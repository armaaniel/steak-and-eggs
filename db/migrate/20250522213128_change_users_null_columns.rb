class ChangeUsersNullColumns < ActiveRecord::Migration[8.0]
  def change
    change_column_null(:users,:gender,false)
    change_column_null(:users,:first_name,false)
    change_column_null(:users,:last_name,false)
    change_column_null(:users,:date_of_birth,false)
  end
end
