class AddControllerAndActionToTraces < ActiveRecord::Migration[8.0]
  def change
    add_column(:traces, :controller, :string)
    add_column(:traces, :action, :string)
  end
end
