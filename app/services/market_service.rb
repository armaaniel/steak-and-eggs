class MarketService
  class InsufficientFundsError < StandardError; end
  class InsufficientSharesError < StandardError; end
  class ApiError < StandardError; end

  MARKET_ZONE = 'America/New_York'
  MARKET_OPEN_MINUTE = (9 * 60) + 30
  MARKET_CLOSE_MINUTE = 16 * 60
  INTRADAY_TIMESPANS = ['minute', 'hour']

  DEFAULT_CHART_RANGE = '1D'

  CHART_RANGES = {
    '1D'  => {multiplier: 5,  timespan: 'minute', ttl: 5.minutes,  from: -> { Date.current - 7.days }},
    '1W'  => {multiplier: 30, timespan: 'minute', ttl: 15.minutes, from: -> { Date.current - 7.days }},
    '1M'  => {multiplier: 1,  timespan: 'hour',   ttl: 1.hour,     from: -> { Date.current - 1.month }},
    '3M'  => {multiplier: 1,  timespan: 'day',    ttl: 1.hour,     from: -> { Date.current - 3.months }},
    'YTD' => {multiplier: 1,  timespan: 'day',    ttl: 1.hour,     from: -> { Date.current.beginning_of_year }},
    '1Y'  => {multiplier: 1,  timespan: 'day',    ttl: 1.hour,     from: -> { Date.current - 1.year }},
    '5Y'  => {multiplier: 1,  timespan: 'week',   ttl: 1.hour,     from: -> { Date.current - 5.years }}
  }

  def self.buy(symbol:, quantity:, user_id:)
    stock_string = RedisService.safe_get("price:#{symbol}")
    stock_price = BigDecimal(stock_string || "0")
    raise(StandardError) if stock_price <=0

    ActiveSupport::Notifications.instrument("MarketService.buy") do
      trade_value = quantity*stock_price
      transaction = nil

      ActiveRecord::Base.transaction do
        user = User.lock.find(user_id)
        position = Position.lock.find_by(user_id:user_id, symbol: symbol)

        raise(InsufficientFundsError) if user.balance < trade_value

        user.balance -= trade_value
        user.save!

          if position
            new_quantity = (position.shares + quantity)
            new_average = ((position.shares * position.average_price) + trade_value) / new_quantity

            position.update!(average_price: new_average, shares: new_quantity)
          else
            new_average = stock_price
            Position.create!(user_id:user_id, symbol: symbol, shares: quantity, average_price:new_average)
          end
          transaction = Transaction.create!(symbol: symbol, quantity: quantity, value: trade_value, transaction_type: 'Buy', user_id: user_id,
          market_price:stock_price, average_price:new_average)
          
          end
          CacheService.invalidate_user(user_id: user_id)
          RedisService.safe_del("positions:#{user_id}")

          {symbol: transaction.symbol, quantity: transaction.quantity, value: transaction.value,
            market_price: transaction.market_price}
          
        end
      end

  def self.sell(symbol:, quantity:, user_id:)
    stock_string = RedisService.safe_get("price:#{symbol}")
    stock_price = BigDecimal(stock_string || "0")
    raise(StandardError, "Unable to fetch Stock Price for #{symbol}") if stock_price <=0

    ActiveSupport::Notifications.instrument("MarketService.sell") do
      trade_value = quantity*stock_price
      transaction = nil

      ActiveRecord::Base.transaction do
        user = User.lock.find(user_id)
        position = Position.lock.find_by(user_id:user_id, symbol: symbol)

        raise(InsufficientSharesError) if position.nil? || position.shares < quantity

        realized_pnl = (trade_value - (position.average_price * quantity))
        avg_price = position.average_price

        user.balance += trade_value
        user.save!

        if position.shares == quantity
          position.destroy!
        else
          position.update!(shares: position.shares - quantity)
        end
        transaction = Transaction.create!(symbol:symbol, quantity:quantity, value:trade_value, transaction_type:'Sell', user_id:user_id,
        realized_pnl: realized_pnl, market_price:stock_price, average_price:avg_price)
        
        end
        CacheService.invalidate_user(user_id: user_id)
        RedisService.safe_del("positions:#{user_id}")

        {symbol: transaction.symbol, quantity: transaction.quantity, value: transaction.value, realized_pnl: transaction.realized_pnl,
          market_price: transaction.market_price}
      end
    end

  def self.marketprice(symbol:)
    ActiveSupport::Notifications.instrument("MarketService.marketprice") do
      cached_price = RedisService.safe_get("price:#{symbol}")
      cached_open = RedisService.safe_get("open:#{symbol}")

      if cached_price
        return {price: cached_price, open: cached_open}
      end

      raise ApiError
    end
  end

  def self.marketdata(symbol:)
    payload = {symbol: symbol, used_redis:false, used_api:false}

    ActiveSupport::Notifications.instrument('MarketService.marketdata', payload) do
      cached = RedisService.safe_get("market:#{symbol}")

      if cached
        payload[:used_redis] = true
        return cached
      end

      payload[:used_api] = true

      uri=URI("https://api.polygon.io/v3/snapshot?ticker=#{symbol}&apiKey=#{ENV['API_KEY']}")
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 1
      http.read_timeout = 2
      
      response = http.request(Net::HTTP::Get.new(uri))
      raise ApiError unless response.code == '200'

      body = JSON.parse(response.body)

      data = {open: body['results'][0]['session']['open'], high: body['results'][0]['session']['high'],
        low:body['results'][0]['session']['low'], volume:body['results'][0]['session']['volume']}

      RedisService.safe_setex("market:#{symbol}", 5.minutes.to_i, data.to_json)
      data
    end
  end

  def self.companydata(symbol:)
    payload = {symbol: symbol, used_redis: false, used_api: false}

    ActiveSupport::Notifications.instrument("MarketService.companydata", payload) do
      cached = RedisService.safe_get("company:#{symbol}")

      if cached
        payload[:used_redis] = true
        return cached
      end

      payload[:used_api] = true

      uri=URI("https://api.polygon.io/v3/reference/tickers/#{symbol}?apiKey=#{ENV['API_KEY']}")
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 1
      http.read_timeout = 2
      
      response = http.request(Net::HTTP::Get.new(uri))
      raise ApiError unless response.code == '200'

      body = JSON.parse(response.body)
      data = {market_cap: body['results']['market_cap'], description: body['results']['description']}

      RedisService.safe_setex("company:#{symbol}", 3.days.to_i, data.to_json)
      data
    end
  end

  def self.chartdata(symbol:, range: DEFAULT_CHART_RANGE)
    config = CHART_RANGES.fetch(range)
    payload = {symbol: symbol, range: range, used_redis: false, used_api: false}

    ActiveSupport::Notifications.instrument("MarketService.chartdata", payload) do
      cached = RedisService.safe_get("chart:#{symbol}:#{range}")
      if cached
        payload[:used_redis] = true
        return cached
      end

      payload[:used_api] = true

      from = config[:from].call
      uri=URI("https://api.polygon.io/v2/aggs/ticker/#{symbol}/range/#{config[:multiplier]}/#{config[:timespan]}/#{from}/#{Date.current}?adjusted=true&sort=asc&limit=50000&apiKey=#{ENV['API_KEY']}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 0.5
      http.read_timeout = 2.5

      response = http.request(Net::HTTP::Get.new(uri))
      raise ApiError unless response.code == '200'

      body=JSON.parse(response.body)
      intraday = INTRADAY_TIMESPANS.include?(config[:timespan])

      bars = (body['results'] || []).map do |result|
        {time: Time.at(result['t']/1000).in_time_zone(MARKET_ZONE), open: result['o'], close: result['c']}
      end

      points = intraday ? session_points(bars) : bars.map { |bar| {time: bar[:time], value: bar[:close], open: bar[:open]} }
      points = latest_session(points) if range == '1D'

      first = points.first
      points = [first.merge(value: first[:open])] + points.drop(1) if first

      date_format = intraday ? "%Y-%m-%d %H:%M" : "%Y-%m-%d"
      data = points.map { |point| {date: point[:time].strftime(date_format), value: point[:value]} }

      RedisService.safe_setex("chart:#{symbol}:#{range}", config[:ttl].to_i, data.to_json)
      data
    end
  end

  def self.session_points(bars)
    bars.filter_map do |bar|
      minutes = (bar[:time].hour * 60) + bar[:time].min

      if minutes >= MARKET_OPEN_MINUTE && minutes < MARKET_CLOSE_MINUTE
        {time: bar[:time], value: bar[:close], open: bar[:open]}
      elsif minutes == MARKET_CLOSE_MINUTE
        {time: bar[:time], value: bar[:open], open: bar[:open]}
      end
    end
  end
  private_class_method :session_points

  def self.latest_session(points)
    return points if points.empty?

    by_day = points.group_by { |point| point[:time].to_date }
    by_day[by_day.keys.max]
  end
  private_class_method :latest_session
end
