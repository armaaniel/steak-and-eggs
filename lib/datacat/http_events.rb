module Datacat
  module HttpEvents
    def request(req, body = nil, &block)
      return super if @datacat_announced

      @datacat_announced = true
      begin
        ActiveSupport::Notifications.instrument('request.http', method: req.method, host: address) { super }
      ensure
        @datacat_announced = false
      end
    end
  end
end
