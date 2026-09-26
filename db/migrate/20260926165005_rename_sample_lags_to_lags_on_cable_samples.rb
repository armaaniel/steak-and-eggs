class RenameSampleLagsToLagsOnCableSamples < ActiveRecord::Migration[8.0]
  def change
    rename_column :cable_samples, :sample_lags, :lags
  end
end
