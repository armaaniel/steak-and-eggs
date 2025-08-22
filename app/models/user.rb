class User < ApplicationRecord
  after_update(:clear_cache, if: :saved_change_to_balance?)
  
  has_secure_password
  has_many(:positions)
  has_many(:transactions)
  has_many(:portfolio_records)
  validates(:username, presence: true, uniqueness: {case_sensitive:false}, length:{maximum:20}, 
  format: {with: /\A[a-zA-Z0-9_]+\z/})
  
  validates(:balance, numericality: { greater_than_or_equal_to: 0 })
  
  private
  
  def clear_cache
    Rails.cache.delete("user_#{id}")
  end
  
end
