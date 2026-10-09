class SystemController < ApplicationController
  def health
    render(json:{status:'ok', time: Time.current}, status:200)
  end

  def not_found
    render(json:{error:'Not Found'}, status: 404)
  rescue => e
    report_error(e)
    render(json:{error:'Not Found'}, status: 404)
  end
end
