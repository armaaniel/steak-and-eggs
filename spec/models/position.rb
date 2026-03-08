require 'rails_helper'

RSpec.describe(Position, type: :model) do
  let(:user) { create(:user) }

  let(:valid_position) do
    Position.new(user: user, symbol: "TSLA", shares: 10, average_price: 100, name: "Tesla, Inc.")
  end

  describe "validations" do
    it "is valid with valid attributes" do
      expect(valid_position).to(be_valid)
    end

    it "requires a symbol" do
      valid_position.symbol = nil
      expect(valid_position).not_to(be_valid)
    end

    it "requires shares to be greater than zero" do
      valid_position.shares = 0
      expect(valid_position).not_to(be_valid)
    end

    it "rejects negative shares" do
      valid_position.shares = -5
      expect(valid_position).not_to(be_valid)
    end

    it "requires average_price to be greater than zero" do
      valid_position.average_price = 0
      expect(valid_position).not_to(be_valid)
    end

    it "rejects negative average_price" do
      valid_position.average_price = -10
      expect(valid_position).not_to(be_valid)
    end

    it "requires a user" do
      valid_position.user = nil
      expect(valid_position).not_to(be_valid)
    end

    it "requires symbol to be unique per user" do
      valid_position.save!

      duplicate = Position.new(user: user, symbol: "TSLA", shares: 5, average_price: 50, name: "Tesla, Inc.")
      expect(duplicate).not_to(be_valid)
    end

    it "allows same symbol for different users" do
      valid_position.save!

      other_user = create(:user)
      other_position = Position.new(user: other_user, symbol: "TSLA", shares: 5, average_price: 50, name: "Tesla, Inc.")
      expect(other_position).to(be_valid)
    end
  end
end