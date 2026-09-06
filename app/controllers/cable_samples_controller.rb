class CableSamplesController < ApplicationController
  MAX_SAMPLES = 1000

  def create
    return head(:forbidden) unless synthetic?
    return head(:bad_request) if params[:samples].blank?
    return head(:payload_too_large) if params[:samples].size > MAX_SAMPLES

    rows = params[:samples].map do |sample|
      {
        run_id:      params[:run_id],
        at:          Time.at(sample[:at].to_f / 1000).utc,
        source:      'client',
        vu:          sample[:vu],
        frames:      sample[:frames],
        sum_lag_ms:  sample[:sum_lag_ms],
        sample_lags: sample[:sample_lags],
        suspect:     sample[:suspect]
      }
    end

    CableSample.insert_all(rows)
    head(:created)
  rescue ActiveRecord::StatementInvalid => e
    Sentry.capture_exception(e)
    head(:unprocessable_entity)
  end
end
