class RunMetric < ApplicationRecord
  def self.for_run(run_id:, metric:)
    where(run_id: run_id, metric: metric).order(:at)
  end
end
