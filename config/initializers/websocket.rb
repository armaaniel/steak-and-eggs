Rails.application.config.after_initialize do
  Thread.new do
    
    if Rails.env.production?
      
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
    
    rescue Dry::Struct::Error, Dry::Types::SchemaError, Dry::Types::ConstraintError => e
      Rails.logger.info "Max connections reached - this worker will skip websocket (PID: #{Process.pid})"
    
    rescue => e
      Sentry.capture_exception(e)
    end
  end
end