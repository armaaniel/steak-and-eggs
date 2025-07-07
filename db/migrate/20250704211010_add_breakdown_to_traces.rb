class AddBreakdownToTraces < ActiveRecord::Migration[8.0]
  def change
    add_column(:traces, :breakdown, :json)
  end
end
