module Datacat
  class TracingListener
    ROOT = 'process_action.action_controller'
    PATTERN = /\.datacat\z|\Aprocess_action\.action_controller\z/

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

    def start(name, id, payload)
      if name != ROOT
        Tracer.current&.open(name.delete_suffix('.datacat'), 'app')
      elsif traced?(payload)
        Tracer.create.open("#{payload[:controller]}##{payload[:action]}", 'app')
      else
        Tracer.clear
      end
    rescue => e
      Sentry.capture_exception(e)
    end

    def finish(name, id, payload)
      tracer = Tracer.current or return
      span = tracer.close

      if name == ROOT
        TRACE_QUEUE.push(trace(tracer, span, payload))
      else
        tracer.breakdown[span[:name]] = payload.except(:exception_object, :exception).merge(duration: span[:duration])
      end
    rescue => e
      Sentry.capture_exception(e)
    ensure
      Tracer.clear if name == ROOT
    end

    private

    def traced?(payload)
      payload[:action] != 'not_found' && TRACKED_ROUTES.any? { |route| payload[:path]&.start_with?(route) }
    end

    def trace(tracer, root, payload)
      now = Time.current

      {
        endpoint: "#{payload[:method]} #{payload[:path].split('?').first}",
        duration: root[:duration],
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
        breakdown: tracer.breakdown.presence,
        spans: tracer.spans,
        created_at: now,
        updated_at: now
      }
    end
  end
end
