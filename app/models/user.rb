class User < ApplicationRecord
  has_secure_password
  has_many(:positions)
  validates(:email, presence: true, uniqueness: true)
end
