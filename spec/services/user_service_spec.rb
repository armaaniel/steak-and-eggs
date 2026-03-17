require 'rails_helper'

RSpec.describe(UserService) do
  let(:user) { create(:user) }

  before do
    allow(RedisService).to(receive(:safe_del))
  end

  describe("signup") do
    it("creates a user and initial portfolio record") do
      result = UserService.signup(username: "newuser", password: "password123")

      expect(result).to(be_a(User))
      expect(result.username).to(eq("newuser"))

      record = PortfolioRecord.find_by(user_id: result.id)
      expect(record.portfolio_value).to(eq(0))
      expect(record.date).to(eq(Date.current))
    end

    it("raises RecordInvalid on duplicate username") do
      User.create!(username: "taken", password: "password123")

      expect {
        UserService.signup(username: "taken", password: "password123")
      }.to(raise_error(ActiveRecord::RecordInvalid))
    end

    it("does not create portfolio record if user creation fails") do
      User.create!(username: "taken", password: "password123")
      initial_count = PortfolioRecord.count

      begin
        UserService.signup(username: "taken", password: "password123")
      rescue ActiveRecord::RecordInvalid
      end

      expect(PortfolioRecord.count).to(eq(initial_count))
    end
  end

  describe("authenticate") do
    it("returns user on valid credentials") do
      result = UserService.authenticate(username: user.username, password: "password123")

      expect(result).to(eq(user))
    end

    it("returns false on wrong password") do
      result = UserService.authenticate(username: user.username, password: "wrong")

      expect(result).to(be(false))
    end

    it("returns nil when user does not exist") do
      result = UserService.authenticate(username: "nobody", password: "password")

      expect(result).to(be_nil)
    end
  end

  describe("deposit") do
    before do
      allow(PositionService).to(receive(:get_aum).and_return({ aum: 10500 }))
    end

    it("increases balance and creates transaction") do
      UserService.deposit(amount: BigDecimal("500"), user_id: user.id)

      expect(user.reload.balance).to(eq(10500))

      transaction = Transaction.find_by(user_id: user.id, transaction_type: "Deposit")
      expect(transaction.value).to(eq(500))
      expect(transaction.symbol).to(eq("USD"))
    end

    it("creates or updates portfolio record for today") do
      UserService.deposit(amount: BigDecimal("500"), user_id: user.id)

      record = PortfolioRecord.find_by(user_id: user.id, date: Date.current)
      expect(record.portfolio_value).to(eq(10500))
    end

    it("invalidates redis cache") do
      expect(RedisService).to(receive(:safe_del).with("portfolio:#{user.id}"))
      expect(RedisService).to(receive(:safe_del).with("activity:#{user.id}"))

      UserService.deposit(amount: BigDecimal("500"), user_id: user.id)
    end
  end

  describe("delete_account") do
    it("destroys the user when password is correct") do
      user_id = user.id
      UserService.delete_account(user_id: user_id, password: "password123")

      expect(User.find_by(id: user_id)).to(be_nil)
    end

    it("raises when password is incorrect") do
      expect {
        UserService.delete_account(user_id: user.id, password: "wrong")
      }.to(raise_error(StandardError))

      expect(User.find_by(id: user.id)).to(be_present)
    end

    it("clears cache after deletion") do
      expect(RedisService).to(receive(:safe_del).with("portfolio:#{user.id}"))
      expect(RedisService).to(receive(:safe_del).with("activity:#{user.id}"))

      UserService.delete_account(user_id: user.id, password: "password123")
    end
  end

  describe("change_password") do
    it("updates the password when current password is correct") do
      UserService.change_password(user_id: user.id, current_password: "password123", new_password: "newpass456")

      expect(UserService.authenticate(username: user.username, password: "newpass456")).to(be_truthy)
    end

    it("raises when current password is incorrect") do
      expect {
        UserService.change_password(user_id: user.id, current_password: "wrong", new_password: "newpass456")
      }.to(raise_error(StandardError))

      expect(UserService.authenticate(username: user.username, password: "password123")).to(be_truthy)
    end
  end

  describe("withdraw") do
    before do
      allow(PositionService).to(receive(:get_aum).and_return({ aum: 9500 }))
    end

    it("decreases balance and creates transaction") do
      UserService.withdraw(amount: BigDecimal("500"), user_id: user.id)

      expect(user.reload.balance).to(eq(9500))

      transaction = Transaction.find_by(user_id: user.id, transaction_type: "Withdraw")
      expect(transaction.value).to(eq(500))
      expect(transaction.symbol).to(eq("USD"))
    end

    it("creates or updates portfolio record for today") do
      UserService.withdraw(amount: BigDecimal("500"), user_id: user.id)

      record = PortfolioRecord.find_by(user_id: user.id, date: Date.current)
      expect(record.portfolio_value).to(eq(9500))
    end

    it("raises when withdrawing more than balance") do
      expect {
        UserService.withdraw(amount: BigDecimal("20000"), user_id: user.id)
      }.to(raise_error(StandardError))

      expect(user.reload.balance).to(eq(10000))
      expect(Transaction.find_by(user_id: user.id, transaction_type: "Withdraw")).to(be_nil)
    end

    it("invalidates redis cache") do
      expect(RedisService).to(receive(:safe_del).with("portfolio:#{user.id}"))
      expect(RedisService).to(receive(:safe_del).with("activity:#{user.id}"))

      UserService.withdraw(amount: BigDecimal("500"), user_id: user.id)
    end
  end
end