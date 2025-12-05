Rails.application.config.after_initialize do
  if Rails.env.production?
    
    HOLIDAYS = [
      Date.new(2025, 1, 1),
      Date.new(2025, 1, 20),
      Date.new(2025, 2, 17),
      Date.new(2025, 4, 18),
      Date.new(2025, 5, 26),
      Date.new(2025, 6, 19),
      Date.new(2025, 7, 4),
      Date.new(2025, 11, 27),
      Date.new(2025, 12, 25),
    ]
    
    market_open = -> {
      now = Time.current.in_time_zone('Eastern Time (US & Canada)')
      return false if now.saturday? || now.sunday?
      return false if now.to_date.in?(HOLIDAYS)
      (now.hour == 9 && now.min >= 30) || (now.hour >= 10 && now.hour < 16)
    }
        
    Thread.new do
      loop do
        
        @queue = Thread::Queue.new
        @last = Time.current
        @connection_refused = false
        puts("starting websocket at #{@last}")
        
        subscriber = Thread.new do
          client = Polygonio::Websocket::Client.new("stocks", ENV['API_KEY'], delayed: true)
          tickers = Ticker.pluck(:symbol)
          symbols = "A.#{tickers.join(',A.')}"
          
          client.subscribe(symbols) do |message|
            message.each do |data|
              @last = Time.current
              @queue.push(data)
            end
          end
        rescue => e
          @connection_refused = true
          puts ("connection refused at #{Time.current}, #{e.class}: #{e.message}, breaking")
        end
        
        consumer = Thread.new do
          loop do
            data = @queue.pop
            RedisService.safe_setex("price:#{data.sym}", 6.days.to_i, data.c)
            RedisService.safe_setex("open:#{data.sym}", 6.days.to_i, data.op)
            ActionCable.server.broadcast("price_channel:#{data.sym}", data.c)
          rescue => e
            Sentry.capture_exception(e)
          end
        end
        
        loop do
          sleep(60)
          puts("last message at #{@last}, time: #{Time.current}")
          break unless subscriber.alive?
          break unless consumer.alive?
          break if market_open.call && Time.current - @last > 5.minutes
        end
        
        subscriber.kill
        consumer.kill
        
        puts("breaking at #{Time.current}: last at #{@last} - #{@connection_refused} (false = reconnect, true = break)")
        
        break if @connection_refused
        
        sleep(30)
      end
    end
  end
end
