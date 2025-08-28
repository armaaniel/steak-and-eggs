Sidekiq.configure_server do |config|
  config.redis = { url: ENV['REDIS_URL'] }
  
  Sidekiq::Cron::Job.create(name: 'Portfolio Record Worker', cron: '5 14 * * *', class: 'PortfolioRecordWorker')
  
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV['REDIS_URL'] }
end
