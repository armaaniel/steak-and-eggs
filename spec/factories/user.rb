FactoryBot.define do
  factory(:user) do
    sequence(:username) { |n| "test_user#{n}" }
    password { "password123" }
    balance { 10000 }
  end
end