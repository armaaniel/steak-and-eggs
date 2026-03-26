source "https://rubygems.org"

gem "rails", "~> 8.0.1"
gem "puma", ">= 5.0"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

gem 'lograge'

gem 'rspec-rails'
gem 'factory_bot_rails'

gem 'redis'

gem 'pg'

gem 'jwt'

gem 'sidekiq'
gem 'sidekiq-cron'

gem 'sentry-ruby'
gem 'sentry-rails'

gem 'oj'

gem 'bcrypt'

gem 'polygonio', git: 'https://github.com/armaaniel/pr.git'

gem 'rack-cors'

gem 'graphql'

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem 'dotenv-rails'
end
