class RedisService
  def self.safe_get(key)
    REDIS.get(key)
  rescue Redis::BaseError => e
    Sentry.capture_exception(e)
    nil
  end

  def self.safe_set(key, value)
    REDIS.set(key, value)
  rescue Redis::BaseError => e
    Sentry.capture_exception(e)
    nil
  end

  def self.safe_setex(key, time, value)
    REDIS.setex(key, time, value)
  rescue Redis::BaseError => e
    Sentry.capture_exception(e)
    nil
  end

  def self.safe_del(*keys)
    REDIS.del(*keys)
  rescue Redis::BaseError => e
    Sentry.capture_exception(e)
    nil
  end

  def self.safe_delete_matching(pattern)
    REDIS.scan_each(match: pattern, count: 1000).each_slice(500).sum { |keys| REDIS.del(*keys) }
  rescue Redis::BaseError => e
    Sentry.capture_exception(e)
    nil
  end

  def self.safe_mget(*keys)
    REDIS.mget(*keys)
  rescue Redis::BaseError => e
    Sentry.capture_exception(e)
    []
  end
end
