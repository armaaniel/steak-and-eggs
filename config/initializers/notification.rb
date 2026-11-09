Rails.application.config.after_initialize do
  RedisClient.register(Datacat::RedisEvents)
  Net::HTTP.prepend(Datacat::HttpEvents)
  AbstractController::Callbacks.prepend(Datacat::CallbackEvents)
  ActionController::Renderers.prepend(Datacat::RenderEvents)

  next if Rails.env.test?

  Thread.new do
    loop do
      sleep 1
      
      batch = []
      begin
        loop { batch.push(Datacat::TRACE_QUEUE.pop(true)) }
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

  ActiveSupport::Notifications.subscribe(Datacat::TracingListener::PATTERN, Datacat::TracingListener.new)
end