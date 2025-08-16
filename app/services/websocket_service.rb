class WebsocketService
  def self.subscribe_to
        
    client = Polygonio::Websocket::Client.new("stocks", "BwLaqIrn3PJnY6NfIDBaEtsqycllj8lE", delayed: true)
    symbols = Ticker.pluck(:symbol)
    ticker_symbols = "A.#{symbols.join(',A.')}"
    
    client.subscribe(ticker_symbols) do |event|
      event.each do |data|
                
        RedisService.safe_setex("price:#{data.sym}", 518400, data.c)
        RedisService.safe_setex("open:#{data.sym}", 518400, data.op)
        
        ActionCable.server.broadcast("price_channel:#{data.sym}", data.c)
        
      rescue => e 
        Sentry.capture_exception(e)
      end
    end
  rescue => e
    Sentry.capture_exception(e)
    sleep 10 
  end
end

      