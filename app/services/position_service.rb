class PositionService
  def self.find_position(symbol:, user_id:)
    ActiveSupport::Notifications.instrument("PositionService.find_position", used_db: true) do
      position = Position.find_by(user_id: user_id, symbol: symbol)

      if position
        {average_price: position.average_price, shares: position.shares, symbol: position.symbol}
      end
    end
  end

  def self.get_aum(user_id:, balance:)
    ActiveSupport::Notifications.instrument("PositionService.get_aum", payload) do
      payload[:used_redis] = false
      positions = PositionService.find_positions(user_id:user_id)
      return {aum:balance, balance:balance} if positions.empty?
      
      payload[:used_redis] = true
      
      price_keys = positions.map do |position|
        "price:#{position[:symbol]}"
      end
      
      open_keys = positions.map do |position|
        "open:#{position[:symbol]}"
      end

      opens = RedisService.safe_mget(open_keys)

      prices = RedisService.safe_mget(*price_keys)
      zip = positions.zip(prices, opens)

      priced_positions = zip.map do |position, price, open|
        position.merge(price: price.to_f, open:open.to_f)
      end

      aum = priced_positions.inject(balance) do |acc, position|
        acc + (position[:price] * position[:shares])
      end

      {aum:aum, positions:priced_positions, balance: balance}
    end
  end

  def self.portfolio_records(user_id:)
    payload = {used_redis: false, used_db: false}

    ActiveSupport::Notifications.instrument("PositionService.portfolio_records", payload) do
      cached = RedisService.safe_get("portfolio:#{user_id}")

      if cached
        payload[:used_redis] = true
        return cached
      end

      payload[:used_db] = true

      data = PortfolioRecord.where(user_id:user_id).order(:date).pluck(:date, :portfolio_value)

      values = data.map do |date, value|
        {date: date, value: value.to_f}
      end

      if values.length < 2
        values = [{date:Date.current, value:0.00}, {date:Date.current, value:values.first[:value]}]
      end

      RedisService.safe_setex("portfolio:#{user_id}", 6.hours.to_i, values.to_json)

      values
    end
  end

  private

  def self.find_positions(user_id:)
    ActiveSupport::Notifications.instrument("PositionService.find_positions", payload) do
      cached = RedisService.safe_get("positions:#{user_id}")
      
      if cached
        payload[:used_redis] = true
        next JSON.parse(cached, symbolize_names:true)
      end
      
      payload[:used_db] = true
      position = Position.where(user_id: user_id)
      
      positions = position.map do |n|
        {symbol: n.symbol, shares: n.shares, name: n.name, average_price:n.average_price}
      end

      RedisService.safe_setex("positions:#{user_id}", 24.hours.to_i, positions.to_json)
      positions

    rescue => e
      Sentry.capture_exception(e)
      []
    end
  end
end
