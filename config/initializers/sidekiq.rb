Sidekiq.configure_server do |config|
  config.redis = { url: 'redis://localhost:6379/0' }
end

Sidekiq.configure_client do |config|
  config.redis = { url: 'redis://localhost:6379/0' }
end

Sidekiq::Cron::Job.create(name:'daily_margin_call_check',
cron: '30 18 * * 1-5 America/Edmonton',
class: 'PortfolioServiceWorker')
  
Sidekiq::Cron::Job.create(name: 'portfolio_update_10s',
cron: '*/10 * * * * *',  
class: 'PortfolioValuesWorker')