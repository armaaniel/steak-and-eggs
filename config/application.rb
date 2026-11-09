require_relative "boot"

require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_cable/engine"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module SteakAndEggs
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    config.lograge.enabled = true
    config.lograge.ignore_actions = ['SystemController#health']

    config.lograge.custom_options = lambda do |event|
        { time: Time.current }
      end

    config.time_zone = 'Mountain Time (US & Canada)'

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib_once(ignore: %w[assets tasks])
  end
end
