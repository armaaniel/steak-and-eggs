class User < ApplicationRecord
  before_validation { self.username = username&.strip&.downcase }
  after_commit(:clear_cache, if: :saved_change_to_balance?)

  has_secure_password
  has_many(:positions, dependent: :destroy)
  has_many(:transactions, dependent: :destroy)
  has_many(:portfolio_records, dependent: :destroy)
  validates(:username, presence: true, uniqueness: {case_sensitive:false}, length:{maximum:20},
  format: {with: /\A[a-zA-Z0-9_]+\z/})

  validates(:balance, numericality: { greater_than_or_equal_to: 0 })

  private

  def clear_cache
    Rails.cache.delete("user_#{id}")
  end
end
