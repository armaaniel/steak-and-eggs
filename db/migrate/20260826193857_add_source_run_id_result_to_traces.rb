class AddSourceToTraces < ActiveRecord::Migration[8.0]
  def up
    add_column :traces, :source, :string, null: false, default: 'user'
    add_column :traces, :run_id, :uuid
    add_column :traces, :result, :string

    execute "UPDATE traces SET source = 'canary' WHERE synthetic"
    remove_column :traces, :synthetic

    add_index :traces, [:source, :created_at]
    add_index :traces, :run_id, where: 'run_id IS NOT NULL'
  end

  def down
    add_column :traces, :synthetic, :boolean, null: false, default: false
    execute "UPDATE traces SET synthetic = true WHERE source = 'canary'"
    remove_column :traces, :source
    remove_column :traces, :run_id
    remove_column :traces, :result
  end
end