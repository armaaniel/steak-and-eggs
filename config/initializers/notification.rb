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
    '/change_password',
    '/delete_account',
    '/demo'
  ].freeze

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

    if name == 'process_action.action_controller'
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
    else
      current_request[id] ||= {}
      current_request[id][name] = payload.except(:exception_object).merge(duration: duration)
    end
  rescue => e
    Sentry.capture_exception(e)
    current_request.delete(id) if id
  end
end