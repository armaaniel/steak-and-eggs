module Datacat
  module RedisEvents
    def call(command, config)
      ActiveSupport::Notifications.instrument('command.redis', command: command) do |payload|
        payload[:reply] = super
      end
    end
  end
end
