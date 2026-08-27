class CreateLoadSamples < ActiveRecord::Migration[8.0]
  def change
    create_table :load_samples do |t|
      t.uuid :run_id, null: false
      t.uuid :request_id, null: false
      t.datetime :at, null: false
      t.string :route, null: false
      t.integer :duration, null: false
      t.integer :waiting
      t.integer :status
    end

    add_index :load_samples, [:run_id, :at]
  end
end
