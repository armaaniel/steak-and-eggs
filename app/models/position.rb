class Position < ApplicationRecord
  belongs_to(:user)
  validates(:symbol, :shares, :user_id, presence: true)
end
