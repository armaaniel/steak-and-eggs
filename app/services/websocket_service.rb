class WebsocketService
  def self.subscribe_to
        
    client = Polygonio::Websocket::Client.new("stocks", "BwLaqIrn3PJnY6NfIDBaEtsqycllj8lE", delayed: true)
    
    client.subscribe("A.*") do |event|
      event.each do |data|
        
        rounded_price = data.c.round(2)
        
        REDIS.set("price:#{data.sym}", rounded_price)
        
        ActionCable.server.broadcast("price_channel:#{data.sym}", rounded_price)
        
      rescue => e 
        nil
        Sentry.capture_exception(e)
      end
    end
  rescue => e
    nil
    sleep 10 
  end
end

      