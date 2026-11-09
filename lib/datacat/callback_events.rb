module Datacat
  module CallbackEvents
    def process_action(...)
      return super if _process_action_callbacks.none? { |callback| callback.kind == :before }

      @datacat_callbacks = ActiveSupport::Notifications.instrumenter.build_handle('before_action.action_controller', {})
      @datacat_callbacks.start
      super
    ensure
      finish_callbacks
    end

    def send_action(...)
      finish_callbacks
      super
    end

    private

    def finish_callbacks
      @datacat_callbacks&.finish
      @datacat_callbacks = nil
    end
  end
end
