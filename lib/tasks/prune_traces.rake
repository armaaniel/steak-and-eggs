task prune_traces: :environment do
  Trace.where("created_at < ?", 30.days.ago).delete_all
  IngesterSample.where("at < ?", 30.days.ago).delete_all
rescue => e
  Sentry.capture_exception(e)
  raise
end