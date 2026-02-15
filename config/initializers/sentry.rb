Sentry.init do |config|
  config.dsn = 'https://7a1588d22e2adc946c56220233de0be4@o4509516499779584.ingest.us.sentry.io/4509516500893696'
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]

  # Add data like request headers and IP for users,
  # see https://docs.sentry.io/platforms/ruby/data-management/data-collected/ for more info
  config.send_default_pii = true
end
