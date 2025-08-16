class ApplicationController < ActionController::Base
  def not_found
    render(json:{error:'Not Found'}, status: 404)
  end
end