class RefactorUsers < ActiveRecord::Migration[8.0]
  def change
    remove_column(:users,:email,:string)
    remove_column(:users,:first_name,:string)
    remove_column(:users,:last_name,:string)
    remove_column(:users,:date_of_birth,:date)
    remove_column(:users,:gender,:integer)
    remove_column(:users,:middle_name,:string)
    add_column(:users,:username,:string, null:false)
  end
end

    
    
    