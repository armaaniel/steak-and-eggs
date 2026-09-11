class SamplesController < ApplicationController
  MAX_SAMPLES = 1000

  def load_samples
    return head(:forbidden) unless synthetic?
    return head(:bad_request) if params[:samples].blank?
    return head(:payload_too_large) if params[:samples].size > MAX_SAMPLES

    rows = params[:samples].map do |s|
      { run_id: params[:run_id],
        request_id: s[:request_id],
        at: Time.at(s[:at].to_f / 1000).utc,
        route: s[:route],
        duration: s[:duration],
        waiting: s[:waiting],
        status: s[:status] 
      }
    end

    LoadSample.insert_all(rows)
    head(:created)
  rescue ActiveRecord::StatementInvalid => e
    Sentry.capture_exception(e)
    head(:unprocessable_entity)
  end

  def cable_samples
    return head(:forbidden) unless synthetic?
    return head(:bad_request) if params[:samples].blank?
    return head(:payload_too_large) if params[:samples].size > MAX_SAMPLES

    rows = params[:samples].map do |s|
      { run_id: params[:run_id],
        at: Time.at(s[:at].to_f / 1000).utc,
        source: 'client',
        vu: s[:vu],
        frames: s[:frames],
        sum_lag_ms: s[:sum_lag_ms],
        sample_lags: s[:sample_lags],
        clean_frames: s[:clean_frames] 
      }
    end

    CableSample.insert_all(rows)
    head(:created)
  rescue ActiveRecord::StatementInvalid => e
    Sentry.capture_exception(e)
    head(:unprocessable_entity)
  end
end