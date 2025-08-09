class User < ApplicationRecord
  after_update(:clear_cache, if: :saved_change_to_balance?)
  
  has_secure_password
  has_many(:positions)
  has_many(:transactions)
  has_many(:portfolio_records)
  validates(:username, presence: true, uniqueness: true)
  
  private
  
  def clear_cache
    Rails.cache.delete("user_#{id}")
  end
  
end
