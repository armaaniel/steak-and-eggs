Rails.application.config.after_initialize do
  if Rails.env.production?

    HOLIDAYS = [
      Date.new(2026, 1, 1),
      Date.new(2026, 1, 19),
      Date.new(2026, 2, 16),
      Date.new(2026, 4, 3),
      Date.new(2026, 5, 25),
      Date.new(2026, 6, 19),
      Date.new(2026, 7, 3),
      Date.new(2026, 9, 7),
      Date.new(2026, 11, 26),
      Date.new(2026, 12, 25),
    ]

    market_open = -> {
      now = Time.current.in_time_zone('Eastern Time (US & Canada)')
      return false if now.saturday? || now.sunday?
      return false if now.to_date.in?(HOLIDAYS)
      (now.hour == 9 && now.min >= 30) || (now.hour >= 10 && now.hour < 16)
    }

    Thread.new do
      loop do
        @last = Time.current
        @connection_refused = false
        puts("starting websocket at #{@last}")

        subscriber = Thread.new do
          client = Polygonio::Websocket::Client.new("stocks", ENV['API_KEY'], delayed: true)
          tickers = Ticker.pluck(:symbol)
          symbols = "A.#{tickers.join(',A.')}"

          client.subscribe(symbols) do |message|
            @last = Time.current
            message.each do |data|
              RedisService.safe_setex("price:#{data.sym}", 6.days.to_i, data.c)
              RedisService.safe_setex("open:#{data.sym}", 6.days.to_i, data.op)
              ActionCable.server.broadcast("price_channel:#{data.sym}", data.c)
            end
          end
        rescue => e
          if e.message.include?("max_connections")
            @connection_refused = true
            puts ("max connections at #{Time.current}, #{e.class}: #{e.message}, breaking")
          else
            puts ("force disconnect at #{Time.current}, #{e.class}: #{e.message}, breaking into reconnect")
            Sentry.capture_exception(e)
          end
        end

        loop do
          sleep(60)
          puts("last message at #{@last}, time: #{Time.current}")
          break unless subscriber.alive?
          break if market_open.call && Time.current - @last > 5.minutes
        end

        subscriber.kill

        puts("breaking at #{Time.current}: last at #{@last} - #{@connection_refused} (false = reconnect, true = break)")

        break if @connection_refused

        sleep(60)
      end
    end
  end
end
