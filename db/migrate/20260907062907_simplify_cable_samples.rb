class SimplifyCableSamples < ActiveRecord::Migration[8.0]
  def up
    execute('TRUNCATE cable_samples')
    remove_column :cable_samples, :suspect
    add_column :cable_samples, :clean_frames, :integer, null: false, default: 0
  end

  def down
    execute('TRUNCATE cable_samples')
    remove_column :cable_samples, :clean_frames
    add_column :cable_samples, :suspect, :boolean, null: false, default: false
  end
end