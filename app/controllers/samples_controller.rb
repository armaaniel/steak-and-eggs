class SamplesController < ApplicationController
  MAX_SAMPLES = 1000

  before_action(:validate_request)

  rescue_from(ActiveRecord::StatementInvalid) do |e|
    Sentry.capture_exception(e)
    head(:unprocessable_entity)
  end

  def load_samples
    rows = params[:samples].map do |sample|
      { run_id:     params[:run_id],
        request_id: sample[:request_id],
        at:         Time.at(sample[:at].to_f / 1000).utc,
        route:      sample[:route],
        duration:   sample[:duration], # unused but free
        waiting:    sample[:waiting],
        status:     sample[:status] }
    end

    LoadSample.insert_all(rows)
    head(:created)
  end

  def cable_samples
    rows = params[:samples].map do |sample|
      { run_id:       params[:run_id],
        at:           Time.at(sample[:at].to_f / 1000).utc,
        source:       'client',
        vu:           sample[:vu],
        frames:       sample[:frames],
        lags:         sample[:lags] }
    end

    CableSample.insert_all(rows)
    head(:created)
  end

  private

  def validate_request
    return head(:forbidden) unless synthetic?
    return head(:bad_request) unless params[:samples].is_a?(Array)
    return head(:bad_request) if params[:samples].empty?

    head(:payload_too_large) if params[:samples].size > MAX_SAMPLES
  end
end