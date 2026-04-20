class CacheService
  def self.invalidate_user(user_id:)
    Rails.cache.delete("user_#{user_id}")
    RedisService.safe_del("portfolio:#{user_id}")
    RedisService.safe_del("activity:#{user_id}")
  end
end