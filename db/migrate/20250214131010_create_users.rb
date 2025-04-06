class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table(:users) do |n|
      n.string(:name)
      n.string(:email)
      n.json(:client_data)
    end
  end
end
