Rails.application.config.after_initialize do
  if Rails.env.production?
    # Start a monitoring thread that will periodically restart the WebSocket
    Thread.new do
      loop do
        # Create a thread for the WebSocket connection
        websocket_thread = Thread.new do
          begin
            puts("Starting new WebSocket connection at #{Time.current}")
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
            
            # If we ever get here naturally (which we likely won't), log it
            puts("WebSocket connection ended naturally at #{Time.current}")
          rescue => e
            Sentry.capture_exception(e)
            puts("WebSocket error: #{e.message} at #{Time.current}")
          end
        end
        
        # Set maximum lifetime for this connection thread
        max_lifetime = 12.hours
        
        # Wait for that duration
        sleep(max_lifetime)
        
        # After the timeout, kill the WebSocket thread if it's still alive
        if websocket_thread.alive?
          puts("Maximum lifetime reached. Killing WebSocket thread at #{Time.current}")
          websocket_thread.kill
          sleep(30) # Give it a moment to clean up
        end
        
        # Log this cycle completed
        puts("WebSocket cycle completed at #{Time.current}, restarting...")
        
        # Optional: short delay before starting a new connection
        sleep(30)
      end
    end
  end
end