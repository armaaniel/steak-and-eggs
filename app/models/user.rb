class User < ApplicationRecord
  before_validation { self.username = username&.strip&.downcase }

  has_secure_password
  has_many(:positions, dependent: :delete_all)
  has_many(:transactions, dependent: :delete_all)
  has_many(:portfolio_records, dependent: :delete_all)
  validates(:username, presence: true, length:{maximum:20}, format: {with: /\A[a-zA-Z0-9_]+\z/})
  validates(:username, uniqueness: {case_sensitive:false}, if: :will_save_change_to_username?)

  validates(:balance, numericality: { greater_than_or_equal_to: 0 })
end
