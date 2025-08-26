class ApplicationController < ActionController::Base
  
  def health
    render(json:{status:'ok', time: Time.current}, status:200)
  end
  
  def not_found
    render(json:{error:'Not Found'}, status: 404)
  rescue => e
    Sentry.capture_exception(e)
    render(json:{error:'Not Found'}, status: 404)
  end
end