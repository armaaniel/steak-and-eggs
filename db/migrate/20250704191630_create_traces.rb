class CreateTraces < ActiveRecord::Migration[8.0]
  def change
    create_table(:traces) do |t|
      t.string(:endpoint, null:false)
      t.float(:duration)
      t.float(:db_runtime)
      t.float(:view_runtime)
      t.integer(:status)

      t.timestamps
    end
  end
end
