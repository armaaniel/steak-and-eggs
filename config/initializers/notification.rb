Rails.application.config.after_initialize do
  
  TRACKED_ROUTES = [
    '/stocks/',
    '/search',
    '/login',
    '/signup',
    '/deposit',
    '/withdraw',
    '/portfoliochart',
    '/portfoliodata',
    '/activitydata',
    '/graphql',
    '/record',
    '/cable'
  ].freeze

  Thread.new do
    
    current_request = {}
    
    ActiveSupport::Notifications.subscribe(/.*/) do |name, start, finish, id, payload|
            
      duration = (finish - start) * 1000
      
      case name
        
      when /PositionService/
        
        current_request[id] ||= {}
        current_request[id][name] = {duration: duration, used_redis: payload[:used_redis], used_db: payload[:used_db]}
        
      when /Ticker/
        
        current_request[id] ||= {}
        current_request[id][name] = {duration: duration, used_redis: payload[:used_redis], used_db: payload[:used_db],
          term:payload[:term]}          
        
      when /MarketService/
        
        current_request[id] ||= {}
        current_request[id][name] = {duration: duration, used_redis: payload[:used_redis], used_api:payload[:used_api],
          symbol:payload[:symbol]}
        
      when 'process_action.action_controller'
        next if payload[:action] == 'not_found'
        next unless TRACKED_ROUTES.any? { |route| payload[:path]&.start_with?(route) }
        
        Trace.create!(endpoint: "#{payload[:method]} #{payload[:path]}", duration: duration , 
        db_runtime: payload[:db_runtime], view_runtime: payload[:view_runtime], status: payload[:status], 
        controller: payload[:controller], action: payload[:action], breakdown: current_request[id] || {})
                
        current_request.delete(id)
              
      end
    rescue => e
      Sentry.capture_exception(e)
      current_request.delete(id) if id
    end
  end
end