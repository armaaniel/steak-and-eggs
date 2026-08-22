class CreateIngesterSamples < ActiveRecord::Migration[8.0]
  def change
    create_table :ingester_samples do |t|
      t.datetime :at, null: false
      t.uuid :boot_id, null: false
      t.uuid :connection_id
      t.string :kind, null: false, default: 'tick'
      t.string :state, null: false
      t.string :cause
      t.bigint :frames, null: false, default: 0
      t.bigint :events, null: false, default: 0
      t.integer :symbols
      t.integer :max_lag_ms
      t.datetime :last_message_at
      t.datetime :first_message_at
      t.jsonb :detail
    end

    add_index :ingester_samples, :at
    add_index :ingester_samples, [:boot_id, :at]
    add_index :ingester_samples, [:kind, :at]
    add_index :ingester_samples, [:connection_id, :at]
  end
end