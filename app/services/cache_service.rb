class CacheService
  def self.invalidate_user(user_id:, positions: false)
    Rails.cache.delete("user:#{user_id}")
    keys = ["portfolio:#{user_id}", "activity:#{user_id}"]
    keys << "positions:#{user_id}" if positions
    RedisService.safe_del(*keys)
  end
end