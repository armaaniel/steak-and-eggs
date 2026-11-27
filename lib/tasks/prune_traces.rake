BATCH_SIZE = 10_000
BATCH_PAUSE = 0.05  # seconds between batches, to let autovacuum keep up
RETENTION = 31.days

prune = lambda do |scope, label|
  deleted = 0
  scope.in_batches(of: BATCH_SIZE) do |batch|
    deleted += batch.delete_all
    sleep BATCH_PAUSE
  end
  Rails.logger.info("prune_traces: deleted #{deleted} #{label}")
end

task prune_traces: :environment do
  JobRun.track('prune_traces') do
    keep_from = (Time.now.utc - RETENTION).to_date
    oldest = ArchiveService.oldest_day

    (oldest...keep_from).each do |day|
      ArchiveService.export_day(day)
      prune.call(ArchiveService.traces_scope(day), "traces for #{day}")
      prune.call(ArchiveService.ingester_samples_scope(day), "ingester_samples for #{day}")
    end if oldest

    ArchiveService.export_day(Time.now.utc.to_date - 1)
  end
end

namespace :archive do
  task backfill: :environment do
    from = ENV['FROM'] ? Date.parse(ENV['FROM']) : ArchiveService.oldest_day
    to = ENV['TO'] ? Date.parse(ENV['TO']) : Time.now.utc.to_date - 1
    (from..to).each do |day|
      counts = ArchiveService.export_day(day)
      puts "#{day} #{counts.map { |table, rows| "#{table} #{rows}" }.join(', ')}"
    end
  end
end
