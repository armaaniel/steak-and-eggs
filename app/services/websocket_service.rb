class WebsocketService
  def self.subscribe_to(symbols)
    return if symbols.blank?
    
    formatted_symbols = symbols.map do |symb|
      "A.#{symb}"
    end
    
    formatted_symbols_string = formatted_symbols.join(',')
    
    client = Polygonio::Websocket::Client.new("stocks", "BwLaqIrn3PJnY6NfIDBaEtsqycllj8lE", delayed: true)
    
    client.subscribe(formatted_symbols_string) do |event|
      event.each do |data|
        
        REDIS.set(data.sym, data.c)
        
        ActionCable.server.broadcast("price_channel:A.#{data.sym}", data.c)
      end
    end
  end
end

      