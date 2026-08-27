class LoadSamplesController < ApplicationController
  def create
    return head(:forbidden) unless synthetic?
    return head(:payload_too_large) if params[:samples].size > 1000

    rows = params[:samples].map do |s|
      { run_id: params[:run_id],
        request_id: s[:request_id],
        at: Time.at(s[:at].to_f / 1000).utc,
        route: s[:route], duration: s[:duration],
        waiting: s[:waiting], status: s[:status] }
    end

    LoadSample.insert_all(rows)
    head(:created)
  rescue ActiveRecord::StatementInvalid => e
    Sentry.capture_exception(e)
    head(:unprocessable_entity)
  end
end
