require 'rails_helper'

RSpec.describe(CacheService) do
  describe("invalidate_user") do
    it("drops the cached user") do
      allow(RedisService).to(receive(:safe_del))
      expect(Rails.cache).to(receive(:delete).with("user:42"))

      CacheService.invalidate_user(user_id: 42)
    end

    it("deletes the portfolio and activity keys with one command") do
      expect(RedisService).to(receive(:safe_del).with("portfolio:42", "activity:42").once)

      CacheService.invalidate_user(user_id: 42)
    end

    it("adds the positions key to that command when a trade changed them") do
      expect(RedisService).to(receive(:safe_del).with("portfolio:42", "activity:42", "positions:42").once)

      CacheService.invalidate_user(user_id: 42, positions: true)
    end
  end
end
