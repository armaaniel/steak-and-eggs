module Datacat
  module RedisSpans
    MULTI_KEY = %w[MGET DEL EXISTS UNLINK].freeze
    KEYLESS = %w[PING SCAN INFO].freeze

    def call(command, config)
      tracer = RedisSpans.open(command)
      return super unless tracer

      succeeded = false
      reply = super
      succeeded = true
      reply
    ensure
      RedisSpans.close(tracer, command, reply, succeeded) if tracer
    end

    def self.open(command)
      tracer = Tracer.current or return
      tracer.open(name(command), 'redis')
      tracer
    rescue => e
      Sentry.capture_exception(e)
      nil
    end

    def self.close(tracer, command, reply, succeeded)
      tracer.close { succeeded ? details(command, reply) : {} }
    rescue => e
      Sentry.capture_exception(e)
    end

    def self.name(command)
      verb = command[0].to_s.upcase
      keys =
        if MULTI_KEY.include?(verb) then command.drop(1)
        elsif KEYLESS.include?(verb) then []
        else command[1, 1]
        end

      [verb, *keys.map { |key| shape(key) }.uniq].join(' ')
    end

    def self.shape(key)
      prefix = key.to_s[/\A[^:]*:/]
      prefix ? "#{prefix}?" : '?'
    end

    def self.details(command, reply)
      case command[0].to_s.upcase
      when 'GET' then { hit: !reply.nil? }
      when 'MGET' then { hit: reply.none?(&:nil?) }
      else {}
      end
    end
  end
end
