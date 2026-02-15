class DropSolidQueueTables < ActiveRecord::Migration[8.0]
  def up
    # Drop foreign keys first
    remove_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs"
    remove_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs"
    remove_foreign_key "solid_queue_failed_executions", "solid_queue_jobs"
    remove_foreign_key "solid_queue_ready_executions", "solid_queue_jobs"
    remove_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs"
    remove_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs"

    # Then drop all the tables
    drop_table :solid_queue_blocked_executions
    drop_table :solid_queue_claimed_executions
    drop_table :solid_queue_failed_executions
    drop_table :solid_queue_ready_executions
    drop_table :solid_queue_recurring_executions
    drop_table :solid_queue_scheduled_executions
    drop_table :solid_queue_pauses
    drop_table :solid_queue_processes
    drop_table :solid_queue_recurring_tasks
    drop_table :solid_queue_semaphores
    drop_table :solid_queue_jobs  # Drop this last since others reference it
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
