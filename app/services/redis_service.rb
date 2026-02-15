class RedisService
  def self.safe_get(key)
    REDIS.get(key)
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

  def self.safe_del(key)
    REDIS.del(key)
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
