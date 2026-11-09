module Datacat
  class TracingListener
    ROOT = 'process_action.action_controller'
    QUERY = 'sql.active_record'
    TRANSACTION = 'transaction.active_record'
    REDIS = 'command.redis'
    HTTP = 'request.http'
    CALLBACKS = 'before_action.action_controller'
    RENDER = 'render.action_controller'
    PATTERN = /\.datacat\z|\A#{Regexp.union(ROOT, QUERY, TRANSACTION, REDIS, HTTP, CALLBACKS, RENDER)}\z/
    SPAN_FIELDS = %i[spans app_ms sql_ms redis_ms http_ms callbacks_ms render_ms cache_hits cache_misses].freeze

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
        tracer = Tracer.current
        open_span(tracer, name, payload) if tracer
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
      return finish_trace(tracer, payload) if name == ROOT

      span =
        case name
        when QUERY then tracer.close { query_details(payload) }
        when REDIS then tracer.close { redis_details(payload) }
        else tracer.close
        end

      if name.end_with?('.datacat')
        tracer.breakdown[span[:name]] = payload.except(:exception_object, :exception).merge(duration: span[:duration])
      end
    rescue => e
      Sentry.capture_exception(e)
    ensure
      Tracer.clear if name == ROOT
    end

    private

    def open_span(tracer, name, payload)
      case name
      when QUERY then tracer.open(payload[:name].presence || 'SQL', 'sql')
      when TRANSACTION then open_transaction(tracer)
      when REDIS then tracer.open(RedisShape.call(payload[:command]), 'redis')
      when HTTP then tracer.open("#{payload[:method]} #{payload[:host]}", 'http')
      when CALLBACKS then tracer.open('before_action', 'callbacks')
      when RENDER then tracer.open("render #{payload[:renderer]}".strip, 'render')
      else tracer.open(name.delete_suffix('.datacat'), 'app')
      end
    end

    def redis_details(payload)
      return {} if payload[:exception]

      case payload[:command][0].to_s.upcase
      when 'GET' then { hit: !payload[:reply].nil? }
      when 'MGET' then { hit: payload[:reply].none?(&:nil?) }
      else {}
      end
    end

    def query_details(payload)
      if payload[:name] == 'TRANSACTION'
        { name: SqlShape.call(payload[:sql]) || 'TRANSACTION' }
      else
        { sql: SqlShape.call(payload[:sql]), cached: payload[:cached] }.compact
      end
    end

    def open_transaction(tracer)
      inner = tracer.innermost

      if inner && inner[:category] == 'sql' && inner[:name] != 'transaction'
        tracer.wrap_innermost('transaction', 'sql')
      else
        tracer.open('transaction', 'sql')
      end
    end

    def traced?(payload)
      payload[:action] != 'not_found' && TRACKED_ROUTES.any? { |route| payload[:path]&.start_with?(route) }
    end

    def finish_trace(tracer, payload)
      balanced = tracer.balanced?
      row = trace(tracer, tracer.close_root, payload)

      unless balanced
        row.merge!(SPAN_FIELDS.index_with(nil))
        Rails.logger.warn("datacat: #{row[:endpoint]}'s spans didn't nest back to the root, so its row is stored without them")
      end

      TRACE_QUEUE.push(row)
    end

    def trace(tracer, root, payload)
      now = Time.current
      times = tracer.self_times
      hits, misses = tracer.cache_counts(excluding: 'callbacks')

      {
        endpoint: "#{payload[:method]} #{payload[:path].split('?').first}",
        duration: root[:duration],
        db_runtime: payload[:db_runtime],
        app_ms: times['app'],
        sql_ms: times['sql'],
        redis_ms: times['redis'],
        http_ms: times['http'],
        callbacks_ms: times['callbacks'],
        render_ms: times['render'],
        cache_hits: hits,
        cache_misses: misses,
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
