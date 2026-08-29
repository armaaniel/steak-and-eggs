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
    '/cable',
    '/change_password',
    '/delete_account',
    '/demo'
  ].freeze # denylist got too long (eg next if payload[:path] == '/favicon.ico')

  current_request = Concurrent::Map.new
  trace_queue = Queue.new

  Thread.new do
    while trace = trace_queue.pop
      begin
        Trace.create!(trace)
      rescue => e
        Sentry.capture_exception(e)
      end
    end
  end

  ActiveSupport::Notifications.monotonic_subscribe(
    /\A(PositionService|Ticker|Transaction|MarketService|UserService|GraphQL)\.|\Aprocess_action\.action_controller\z/
  ) do |name, start, finish, id, payload|
    duration = (finish - start) * 1000

    case name

    when /PositionService/
      current_request[id] ||= {}

      if name == "PositionService.find_position"
        current_request[id][name] = {duration: duration, used_db: payload[:used_db]}
      elsif name == "PositionService.get_aum"
        current_request[id][name] = {duration: duration, used_redis: payload[:used_redis]}
      else
        current_request[id][name] = {duration: duration, used_redis: payload[:used_redis], used_db: payload[:used_db]}
      end

    when /Ticker/
      current_request[id] ||= {}
      current_request[id][name] = {duration: duration, used_redis: payload[:used_redis], used_db: payload[:used_db],
        term: payload[:term]}

    when /Transaction/
      current_request[id] ||= {}
      current_request[id][name] = {duration: duration, used_redis: payload[:used_redis], used_db: payload[:used_db]}

    when /MarketService/
      current_request[id] ||= {}

      if name == "MarketService.sell" || name == "MarketService.marketprice"
        current_request[id][name] = {duration: duration}
      elsif name == "MarketService.buy"
        entry = (current_request[id][name] ||= {duration: 0.0, calls: 0})
        entry[:duration] += duration
        entry[:calls] += 1
      else
        current_request[id][name] = {duration: duration, used_redis: payload[:used_redis], used_api: payload[:used_api],
          symbol: payload[:symbol]}
      end

    when /UserService/
      current_request[id] ||= {}
      current_request[id][name] = {duration: duration}

    when /GraphQL/
      current_request[id] ||= {}
      current_request[id][name] = {duration: duration, operation: payload[:operation]}

    when 'process_action.action_controller'
      breakdown = current_request.delete(id)  
      next if payload[:action] == 'not_found'
      next unless TRACKED_ROUTES.any? { |route| payload[:path]&.start_with?(route) }

      trace_queue.push({
        endpoint: "#{payload[:method]} #{payload[:path]}",
        duration: duration,
        db_runtime: payload[:db_runtime],
        view_runtime: payload[:view_runtime] || 0,
        status: payload[:status],
        controller: payload[:controller],
        action: payload[:action],
        user_id: payload[:user_id],
        source: payload[:source] || 'user',
        run_id: payload[:run_id],
        result: payload[:result],
        request_id: payload[:request_id],
        breakdown: breakdown.presence
      })

    end
  rescue => e
    Sentry.capture_exception(e)
    current_request.delete(id) if id
  end
end
