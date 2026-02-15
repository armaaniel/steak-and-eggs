class RemoveForeignKeyAndDropAccountsTable < ActiveRecord::Migration[8.0]
  def change
    remove_foreign_key('accounts', 'users')
    drop_table('accounts')
  end
end
