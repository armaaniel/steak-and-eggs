class CreateAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table(:accounts) do |n|
      n.string(:account_type)
      n.string(:account_name)
      n.json(:positions)
    end
  end
end
