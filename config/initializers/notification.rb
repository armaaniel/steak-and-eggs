Rails.application.config.after_initialize do
  next if Rails.env.test?

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
    loop do
      sleep 1
      
      batch = []
      begin
        loop { batch.push(trace_queue.pop(true)) }
      rescue ThreadError
      end
      
      next if batch.empty?
      
      begin
        Trace.insert_all(batch)
      rescue => e
        Sentry.capture_exception(e)
      end
    end
  end

  ActiveSupport::Notifications.monotonic_subscribe(
    /\.datacat\z|\Aprocess_action\.action_controller\z/
  ) do |name, start, finish, id, payload|
    duration = (finish - start) * 1000

    if name == 'process_action.action_controller'
      breakdown = current_request.delete(id)
      next if payload[:action] == 'not_found'
      next unless TRACKED_ROUTES.any? { |route| payload[:path]&.start_with?(route) }
      now = Time.current

      trace_queue.push({
        endpoint: "#{payload[:method]} #{payload[:path].split('?').first}",
        duration: duration,
        db_runtime: payload[:db_runtime],
        status: payload[:status],
        controller: payload[:controller],
        action: payload[:action],
        user_id: payload[:user_id],
        source: payload[:source] || 'user',
        run_id: payload[:run_id],
        result: payload[:result],
        request_id: payload[:request_id],
        error_class: payload[:error_class] || payload[:exception]&.first,
        error_location: payload[:error_location],
        sentry_event_id: payload[:sentry_event_id],
        breakdown: breakdown.presence,
        created_at: now,
        updated_at: now
      })
      
    else
      span = payload.except(:exception_object, :exception)
      span[:error_class] = payload[:exception].first if payload[:exception]
      current_request[id] ||= {}
      current_request[id][name.delete_suffix('.datacat')] = span.merge(duration: duration)
    end
  rescue => e
    Sentry.capture_exception(e)
    current_request.delete(id)
  end
end