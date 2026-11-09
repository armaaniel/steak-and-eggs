module Datacat
  module RedisShape
    MULTI_KEY = %w[MGET DEL EXISTS UNLINK].freeze
    KEYLESS = %w[PING SCAN INFO].freeze

    def self.call(command)
      verb = command[0].to_s.upcase
      keys =
        if MULTI_KEY.include?(verb) then command.drop(1)
        elsif KEYLESS.include?(verb) then []
        else command[1, 1]
        end

      [verb, *keys.map { |key| key_shape(key) }.uniq].join(' ')
    end

    def self.key_shape(key)
      prefix = key.to_s[/\A[^:]*:/]
      prefix ? "#{prefix}?" : '?'
    end
  end
end
