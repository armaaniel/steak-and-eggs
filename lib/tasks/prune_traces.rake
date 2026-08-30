# Load-test traces are kept with their run, not on a clock: load_samples rows are never
# pruned, so deleting the traces they join on request_id would make every run older than
# 30 days read as a 100% server outage in the compare view.
task prune_traces: :environment do
  Trace.where("created_at < ?", 30.days.ago).where.not(source: 'load').delete_all
  IngesterSample.where("at < ?", 30.days.ago).delete_all
rescue => e
  Sentry.capture_exception(e)
  raise
end
