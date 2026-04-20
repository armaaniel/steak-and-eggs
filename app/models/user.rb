class User < ApplicationRecord
  before_validation { self.username = username&.strip&.downcase }

  has_secure_password
  has_many(:positions, dependent: :destroy)
  has_many(:transactions, dependent: :destroy)
  has_many(:portfolio_records, dependent: :destroy)
  validates(:username, presence: true, uniqueness: {case_sensitive:false}, length:{maximum:20},
  format: {with: /\A[a-zA-Z0-9_]+\z/})

  validates(:balance, numericality: { greater_than_or_equal_to: 0 })
end
