require 'rails_helper'

RSpec.describe(PortfolioRecord, type: :model) do
  let(:user) { create(:user) }

  let(:valid_record) do
    PortfolioRecord.new(user: user, date: Date.current, portfolio_value: 10000)
  end

  describe "validations" do
    it "is valid with valid attributes" do
      expect(valid_record).to(be_valid)
    end

    it "requires a user" do
      valid_record.user = nil
      expect(valid_record).not_to(be_valid)
    end

    it "requires portfolio_value to be numeric" do
      valid_record.portfolio_value = "abc"
      expect(valid_record).not_to(be_valid)
    end

    it "allows portfolio_value of zero" do
      valid_record.portfolio_value = 0
      expect(valid_record).to(be_valid)
    end

    it "requires date to be unique per user" do
      valid_record.save!

      duplicate = PortfolioRecord.new(user: user, date: Date.current, portfolio_value: 5000)
      expect(duplicate).not_to(be_valid)
    end

    it "allows same date for different users" do
      valid_record.save!

      other_user = create(:user)
      other_record = PortfolioRecord.new(user: other_user, date: Date.current, portfolio_value: 5000)
      expect(other_record).to(be_valid)
    end
  end
end