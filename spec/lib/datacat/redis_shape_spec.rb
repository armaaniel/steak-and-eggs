require 'rails_helper'

RSpec.describe(Datacat::RedisShape) do
  describe(".call") do
    it("is the command and its key's prefix, never the rest of the key or any value") do
      expect(Datacat::RedisShape.call(['get', 'price:AAPL'])).to(eq('GET price:?'))
      expect(Datacat::RedisShape.call(['set', 'user:42', "\x04\bo:\tUser", 'PX', 86_400_000])).to(eq('SET user:?'))
      expect(Datacat::RedisShape.call(['setex', 'search:apple', 300, '[]'])).to(eq('SETEX search:?'))
    end

    it("lists each distinct key prefix for commands that take several keys") do
      expect(Datacat::RedisShape.call(['mget', 'price:AAPL', 'open:AAPL'])).to(eq('MGET price:? open:?'))
      expect(Datacat::RedisShape.call(['del', 'portfolio:42', 'activity:42', 'portfolio:43'])).to(eq('DEL portfolio:? activity:?'))
    end

    it("hides a key with no colon completely") do
      expect(Datacat::RedisShape.call(['get', 'user_42'])).to(eq('GET ?'))
    end

    it("names a keyless command by itself") do
      expect(Datacat::RedisShape.call(['scan', '0', 'MATCH', 'chart:AAPL:*', 'COUNT', 1000])).to(eq('SCAN'))
    end
  end
end
