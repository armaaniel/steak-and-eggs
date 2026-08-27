class AddRequestIdToTraces < ActiveRecord::Migration[8.0]
  def change
    add_column :traces, :request_id, :uuid
    add_index :traces, :request_id, where: 'request_id IS NOT NULL'
  end
end
