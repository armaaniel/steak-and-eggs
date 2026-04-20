require 'rails_helper'

RSpec.describe(User, type: :model) do
  let(:user) { create(:user) }

  describe "validations" do
    it "is valid with valid attributes" do
      expect(user).to(be_valid)
    end

    it "requires a username" do
      user.username = nil
      expect(user).not_to(be_valid)
    end

    it "requires username to be unique (case insensitive)" do
      create(:user, username: "taken")
      duplicate = build(:user, username: "TAKEN")

      expect(duplicate).not_to(be_valid)
    end

    it "requires username to be 20 characters or less" do
      user.username = "a" * 21
      expect(user).not_to(be_valid)
    end

    it "allows underscores in username" do
      user.username = "test_user"
      expect(user).to(be_valid)
    end

    it "rejects special characters in username" do
      %w[test@user test.user test!user test user test-user].each do |bad_name|
        user.username = bad_name
        expect(user).not_to(be_valid), "expected '#{bad_name}' to be invalid"
      end
    end

    it "requires balance to be non-negative" do
      user.balance = -1
      expect(user).not_to(be_valid)
    end

    it "allows balance of zero" do
      user.balance = 0
      expect(user).to(be_valid)
    end

    it "requires a password on create" do
      user = User.new(username: "newuser")
      expect(user).not_to(be_valid)
    end
  end

  describe "before_validation" do
    it "downcases username" do
      user = User.create!(username: "TestUser", password: "password123")
      expect(user.username).to(eq("testuser"))
    end
  end

  describe "associations" do
    it "has many positions" do
      expect(user).to(respond_to(:positions))
    end

    it "has many transactions" do
      expect(user).to(respond_to(:transactions))
    end

    it "has many portfolio records" do
      expect(user).to(respond_to(:portfolio_records))
    end
  end

end