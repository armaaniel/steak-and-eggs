module Datacat
  module RenderEvents
    def render_to_body(options)
      renderer = _renderers.find { |name| options.key?(name) }
      ActiveSupport::Notifications.instrument('render.action_controller', renderer: renderer) { super }
    end
  end
end
