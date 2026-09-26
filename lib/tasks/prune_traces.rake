BATCH_SIZE = 10_000
BATCH_PAUSE = 0.05  # seconds between batches, to let autovacuum keep up

prune = lambda do |scope, label|
  deleted = 0
  scope.in_batches(of: BATCH_SIZE) do |batch|
    deleted += batch.delete_all
    sleep BATCH_PAUSE
  end
  Rails.logger.info("prune_traces: deleted #{deleted} #{label}")
end

task prune_traces: :environment do
  cutoff = 30.days.ago

  prune.call(Trace.where("created_at < ?", cutoff).where.not(source: 'load'), 'traces')
  prune.call(IngesterSample.where("at < ?", cutoff), 'ingester_samples')
rescue => e
  Sentry.capture_exception(e)
  raise
end
