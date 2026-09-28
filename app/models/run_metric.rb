class RunMetric < ApplicationRecord
  def self.get(run_id:, metric:)
    where(run_id: run_id, metric: metric).order(:at)
  end
end
