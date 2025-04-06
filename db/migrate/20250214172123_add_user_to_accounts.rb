class AddUserToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_reference(:accounts,:user)
    add_foreign_key(:accounts,:users)
  end
end
