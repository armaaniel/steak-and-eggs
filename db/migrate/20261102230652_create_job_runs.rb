class CreateJobRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :job_runs do |t|
      t.string :name, null: false
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.string :error_class
      t.string :sentry_event_id
    end

    add_index :job_runs, [:name, :started_at]
  end
end
