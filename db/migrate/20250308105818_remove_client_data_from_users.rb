class RemoveClientDataFromUsers < ActiveRecord::Migration[8.0]
  def change
    remove_column('users', 'client_data', 'json')
  end
end
