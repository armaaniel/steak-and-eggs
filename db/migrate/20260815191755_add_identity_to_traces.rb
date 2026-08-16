class AddIdentityToTraces < ActiveRecord::Migration[8.0]
  def change
    add_column(:traces, :user_id, :bigint)
    add_column(:traces, :synthetic, :boolean, default: false, null: false)
  end
end