class CreateRunMetrics < ActiveRecord::Migration[8.0]
  def change
    create_table :run_metrics do |t|
      t.uuid :run_id, null: false
      t.string :metric, null: false
      t.datetime :at, null: false
      t.float :minimum
      t.float :maximum
      t.float :average
    end

    add_index :run_metrics, [:run_id, :metric, :at], unique: true
  end
end
