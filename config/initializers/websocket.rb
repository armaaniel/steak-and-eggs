Rails.application.config.after_initialize do
  Thread.new do
    retries = 0
    
    loop do
      client = Polygonio::Websocket::Client.new("stocks", ENV['API_KEY'], delayed: true)
      tickers = Ticker.pluck(:symbol)
      symbols = "A.#{tickers.join(',A.')}"
      retries = 0
      
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
      
    rescue Dry::Struct::Error, Dry::Types::SchemaError, Dry::Types::ConstraintError => e
      retries += 1
      if retries > 3
        Rails.logger.info "Max connections reached - this worker will skip websocket (PID: #{Process.pid})"
        Sentry.capture_exception(e)
        break
      else
        Rails.logger.info "Max connections (#{retries}/3), retrying in 30s"
        sleep 30
      end
    rescue => e
      Sentry.capture_exception(e)
      sleep 10
    end
  end
end