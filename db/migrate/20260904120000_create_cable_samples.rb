class CreateCableSamples < ActiveRecord::Migration[8.0]
  def change
    create_table :cable_samples do |t|
      t.uuid     :run_id, null: false
      t.datetime :at,     null: false
      t.string   :source, null: false
      t.integer  :vu
      t.integer  :frames,  null: false, default: 0
      t.bigint   :sum_lag_ms
      t.integer  :sample_lags, array: true
      t.boolean  :suspect, null: false, default: false

      t.index [:run_id, :at]
    end

    add_check_constraint :cable_samples, "source IN ('publisher', 'client')", name: 'valid_cable_source'
  end
end
