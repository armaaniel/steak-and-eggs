class DropCleanFramesFromCableSamples < ActiveRecord::Migration[8.0]
  def change
    remove_column :cable_samples, :clean_frames, :integer, null: false, default: 0
  end
end