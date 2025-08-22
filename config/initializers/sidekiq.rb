Sidekiq.configure_server do |config|
  config.redis = { url: 'redis://localhost:6379/0' }
  
  Sidekiq::Cron::Job.create(name: 'Portfolio Record Worker', cron: '5 14 * * *', class: 'PortfolioRecordWorker')
  
end

Sidekiq.configure_client do |config|
  config.redis = { url: 'redis://localhost:6379/0' }
end
