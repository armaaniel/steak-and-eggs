require 'rails_helper'

RSpec.describe(RedisService) do
  describe "safe_get" do
    it "returns the value on success" do
      allow(REDIS).to(receive(:get).with("key").and_return("value"))

      expect(RedisService.safe_get("key")).to(eq("value"))
    end

    it "returns nil on Redis error" do
      allow(REDIS).to(receive(:get).and_raise(Redis::BaseError))
      allow(Sentry).to(receive(:capture_exception))

      expect(RedisService.safe_get("key")).to(be_nil)
      expect(Sentry).to(have_received(:capture_exception))
    end
  end

  describe "safe_setex" do
    it "sets value with expiry on success" do
      expect(REDIS).to(receive(:setex).with("key", 300, "value"))

      RedisService.safe_setex("key", 300, "value")
    end

    it "returns nil on Redis error" do
      allow(REDIS).to(receive(:setex).and_raise(Redis::BaseError))
      allow(Sentry).to(receive(:capture_exception))

      expect(RedisService.safe_setex("key", 300, "value")).to(be_nil)
      expect(Sentry).to(have_received(:capture_exception))
    end
  end

  describe "safe_del" do
    it "deletes the key on success" do
      expect(REDIS).to(receive(:del).with("key"))

      RedisService.safe_del("key")
    end

    it "returns nil on Redis error" do
      allow(REDIS).to(receive(:del).and_raise(Redis::BaseError))
      allow(Sentry).to(receive(:capture_exception))

      expect(RedisService.safe_del("key")).to(be_nil)
      expect(Sentry).to(have_received(:capture_exception))
    end
  end

  describe "safe_mget" do
    it "returns values on success" do
      allow(REDIS).to(receive(:mget).with("key1", "key2").and_return(["val1", "val2"]))

      expect(RedisService.safe_mget("key1", "key2")).to(eq(["val1", "val2"]))
    end

    it "returns empty array on Redis error" do
      allow(REDIS).to(receive(:mget).and_raise(Redis::BaseError))
      allow(Sentry).to(receive(:capture_exception))

      expect(RedisService.safe_mget("key1", "key2")).to(eq([]))
      expect(Sentry).to(have_received(:capture_exception))
    end
  end
end