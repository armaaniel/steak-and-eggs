class WebsocketService
  def self.subscribe_to
        
    client = Polygonio::Websocket::Client.new("stocks", "BwLaqIrn3PJnY6NfIDBaEtsqycllj8lE", delayed: true)
    
    client.subscribe("A.*") do |event|
      event.each do |data|
        
        REDIS.set("price:#{data.sym}", data.c)
        
        ActionCable.server.broadcast("price_channel:#{data.sym}", data.c)
      end
    end
  end
end

      