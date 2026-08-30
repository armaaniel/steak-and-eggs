BATCH_SIZE = 10_000
BATCH_PAUSE = 0.05  # seconds between batches, to let autovacuum keep up

# Deleted in batches so a month of rows never lands in one transaction: a single
# delete_all holds row locks for the length of the scan and hands autovacuum a
# table's worth of dead tuples at once.
prune = lambda do |scope, label|
  deleted = 0
  scope.in_batches(of: BATCH_SIZE) do |batch|
    deleted += batch.delete_all
    sleep BATCH_PAUSE
  end
  Rails.logger.info("prune_traces: deleted #{deleted} #{label}")
end

# Load-test traces are kept with their run, not on a clock: load_samples rows are never
# pruned, so deleting the traces they join on request_id would make every run older than
# 30 days read as a 100% server outage in the compare view.
task prune_traces: :environment do
  cutoff = 30.days.ago

  prune.call(Trace.where("created_at < ?", cutoff).where.not(source: 'load'), 'traces')
  prune.call(IngesterSample.where("at < ?", cutoff), 'ingester_samples')
rescue => e
  Sentry.capture_exception(e)
  raise
end
