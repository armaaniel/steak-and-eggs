Rails.application.config.after_initialize do
  
  symbols = Position.select(:symbol).distinct.pluck(:symbol)
  
  Thread.new do
    WebsocketService.subscribe_to(symbols)
  end
end