class CreatePositions < ActiveRecord::Migration[8.0]
  def change
    create_table(:positions) do |n|
      n.string(:symbol)
      n.integer(:shares)
      n.references(:user, foreign_key: true)
      n.timestamps
    end
  end
end
