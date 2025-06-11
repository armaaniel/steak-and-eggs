Rails.application.config.after_initialize do
    
  Thread.new do
    WebsocketService.subscribe_to
  end
end