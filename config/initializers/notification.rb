Rails.application.config.after_initialize do
  
  Thread.new do
    
    ActiveSupport::Notifications.subscribe(/.*/) do |name, start, finish, id, payload|
      
      duration = (finish - start) * 1000
      
      case name
        
      when /MarketService/
        
        current_request[id] ||= {}
        current_request[id][name] = {duration: duration, used_redis: payload[:used_redis], used_api:payload[:used_api],
          symbol:payload[:symbol]}
        
      when 'process_action.action_controller'
        next if payload[:path] == '/favicon.ico'
        next if payload[:path]&.include?('devtools')                     
        
        Trace.create!(endpoint: "#{payload[:method]} #{payload[:path]}", duration: duration , 
        db_runtime: payload[:db_runtime], view_runtime: payload[:view_runtime], status: payload[:status], 
        controller: payload[:controller], action: payload[:action], breakdown: current_request[id] || {})
        
        current_request.delete(id)
        
      end
    end
  end
end

      
