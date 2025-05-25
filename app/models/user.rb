class User < ApplicationRecord
  has_secure_password
  has_many(:positions)
  validates(:email, presence: true, uniqueness: true)
  validates(:first_name, presence: true)
  validates(:last_name, presence: true)
  validates(:date_of_birth, presence: true)
  validates(:gender, presence: true)
  enum(:gender, {

    male:0,
    female:1,
    non_binary:2,
    fluid:3,
    prefer_not_to_say:4

  })
end
