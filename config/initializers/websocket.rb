Rails.application.config.after_initialize do
  Thread.new do
    loop do
              
      client = Polygonio::Websocket::Client.new("stocks", "BwLaqIrn3PJnY6NfIDBaEtsqycllj8lE", delayed: true)
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
    rescue => e
      Sentry.capture_exception(e)
      sleep 10
    end
  end
end