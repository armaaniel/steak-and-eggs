Rails.application.config.after_initialize do
  Thread.new do
    if Rails.env.production?
  
      loop do
        10.times do
          puts("trying to connect to ws, #{Time.current}")
        end
        client = Polygonio::Websocket::Client.new("stocks", ENV['API_KEY'], delayed: true)
        tickers = Ticker.pluck(:symbol)
        symbols = "A.#{tickers.join(',A.')}"
        
        client.subscribe(symbols) do |message|
          message.each do |data|
            RedisService.safe_setex("price:#{data.sym}", 6.days.to_i, data.c)
            RedisService.safe_setex("open:#{data.sym}", 6.days.to_i, data.op)
            ActionCable.server.broadcast("price_channel:#{data.sym}", data.c)
          rescue => e
            Sentry.capture_exception(e)
          end
        rescue => e
          Sentry.capture_exception(e)
        end
        
        Sentry.capture_message("Websocket connection ended, #{Time.current}")
        25.times do
          puts("!!!@@@@@!!!&&& WEBSOCKET DIED &&& $$$$ && && && & & & @@@@ #{Time.current}")
        end 
        
        sleep(900)
        
        10.times do
          puts("trying again at #{Time.current}")
        end
      
      rescue => e
        Sentry.capture_exception(e)
        10.times do 
          puts("I rescued #{e.class} - #{e.message} - #{Time.current}")
        end
        break
      end
    end
  end
end