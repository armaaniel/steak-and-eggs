require 'rails_helper'

RSpec.describe("Users", type: :request) do
  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }

  describe "POST /signup" do
    it "creates user and returns JWT" do
      post "/signup", params: { username: "newuser", password: "password123" }
      
      expect(response).to(have_http_status(200))

      body = JSON.parse(response.body)
      expect(body["token"]).to(be_present)

      decoded = JWT.decode(body["token"], Rails.application.secret_key_base, true, algorithm: 'HS256')
      created_user = User.find(decoded[0]["user_id"])
      expect(created_user.username).to(eq("newuser"))
    end

    it "creates initial portfolio record on signup" do
      post "/signup", params: { username: "newuser", password: "password123" }

      body = JSON.parse(response.body)
      decoded = JWT.decode(body["token"], Rails.application.secret_key_base, true, algorithm: 'HS256')

      record = PortfolioRecord.find_by(user_id: decoded[0]["user_id"])
      expect(record).to(be_present)
      expect(record.portfolio_value).to(eq(0))
    end

    it "returns 422 on duplicate username" do
      create(:user, username: "taken")

      post "/signup", params: { username: "taken", password: "password123" }

      expect(response).to(have_http_status(422))
      expect(JSON.parse(response.body)["error"]).to(include("Username has been taken"))
    end

    it "returns 422 on duplicate username case insensitive" do
      create(:user, username: "taken")

      post "/signup", params: { username: "TAKEN", password: "password123" }

      expect(response).to(have_http_status(422))
    end
  end

  describe "POST /login" do
    it "returns JWT on valid credentials" do
      post "/login", params: { username: user.username, password: "password123" }

      expect(response).to(have_http_status(200))

      body = JSON.parse(response.body)
      expect(body["token"]).to(be_present)

      decoded = JWT.decode(body["token"], Rails.application.secret_key_base, true, algorithm: 'HS256')
      expect(decoded[0]["user_id"]).to(eq(user.id))
    end

    it "is case insensitive on username" do
      post "/login", params: { username: user.username.upcase, password: "password123" }

      expect(response).to(have_http_status(200))
      expect(JSON.parse(response.body)["token"]).to(be_present)
    end

    it "returns 401 on wrong password" do
      post "/login", params: { username: user.username, password: "wrong" }

      expect(response).to(have_http_status(401))
      expect(JSON.parse(response.body)["error"]).to(be_present)
    end

    it "returns 401 for nonexistent user" do
      post "/login", params: { username: "nobody", password: "password123" }

      expect(response).to(have_http_status(401))
    end
  end

  describe "POST /deposit" do
    before do
      allow(PositionService).to(receive(:get_aum).and_return({ aum: 10500 }))
      allow(RedisService).to(receive(:safe_del))
    end

    it "returns 200 on valid deposit" do
      post "/deposit", params: { amount: "500" }, headers: headers

      expect(response).to(have_http_status(200))
      expect(user.reload.balance).to(eq(10500))
    end

    it "returns 422 when amount is zero" do
      post "/deposit", params: { amount: "0" }, headers: headers

      expect(response).to(have_http_status(422))
      expect(JSON.parse(response.body)["error"]).to(eq("Invalid amount"))
    end

    it "returns 422 when amount is negative" do
      post "/deposit", params: { amount: "-100" }, headers: headers

      expect(response).to(have_http_status(422))
      expect(JSON.parse(response.body)["error"]).to(eq("Invalid amount"))
    end

    it "returns 422 when amount is missing" do
      post "/deposit", params: {}, headers: headers

      expect(response).to(have_http_status(422))
    end

    it "returns 401 without auth token" do
      post "/deposit", params: { amount: "500" }

      expect(response).to(have_http_status(401))
    end
  end

  describe "DELETE /delete_account" do
    before do
      allow(RedisService).to(receive(:safe_del))
    end

    it "returns 200 and destroys user with correct password" do
      delete "/delete_account", params: { password: "password123" }, headers: headers

      expect(response).to(have_http_status(200))
      expect(User.find_by(id: user.id)).to(be_nil)
    end

    it "returns 422 when password is wrong" do
      delete "/delete_account", params: { password: "wrong" }, headers: headers

      expect(response).to(have_http_status(422))
      expect(JSON.parse(response.body)["error"]).to(eq("Password is incorrect"))
      expect(User.find_by(id: user.id)).to(be_present)
    end

    it "returns 422 when password is missing" do
      delete "/delete_account", params: {}, headers: headers

      expect(response).to(have_http_status(422))
      expect(JSON.parse(response.body)["error"]).to(eq("password is required"))
    end

    it "returns 401 without auth token" do
      delete "/delete_account", params: { password: "password123" }

      expect(response).to(have_http_status(401))
    end
  end

  describe "POST /change_password" do
    it "returns 200 on valid password change" do
      post "/change_password", params: { current_password: "password123", new_password: "newpass456" }, headers: headers

      expect(response).to(have_http_status(200))
      expect(UserService.authenticate(username: user.username, password: "newpass456")).to(be_truthy)
    end

    it "returns 422 when current password is wrong" do
      post "/change_password", params: { current_password: "wrong", new_password: "newpass456" }, headers: headers

      expect(response).to(have_http_status(422))
      expect(JSON.parse(response.body)["error"]).to(eq("Current password is incorrect"))
    end

    it "returns 422 when current_password is missing" do
      post "/change_password", params: { new_password: "newpass456" }, headers: headers

      expect(response).to(have_http_status(422))
      expect(JSON.parse(response.body)["error"]).to(include("required"))
    end

    it "returns 422 when new_password is missing" do
      post "/change_password", params: { current_password: "password123" }, headers: headers

      expect(response).to(have_http_status(422))
      expect(JSON.parse(response.body)["error"]).to(include("required"))
    end

    it "returns 401 without auth token" do
      post "/change_password", params: { current_password: "password123", new_password: "newpass456" }

      expect(response).to(have_http_status(401))
    end
  end

  describe "POST /withdraw" do
    before do
      allow(PositionService).to(receive(:get_aum).and_return({ aum: 9500 }))
      allow(RedisService).to(receive(:safe_del))
    end

    it "returns 200 on valid withdrawal" do
      post "/withdraw", params: { amount: "500" }, headers: headers

      expect(response).to(have_http_status(200))
      expect(user.reload.balance).to(eq(9500))
    end

    it "returns 422 when amount is zero" do
      post "/withdraw", params: { amount: "0" }, headers: headers

      expect(response).to(have_http_status(422))
      expect(JSON.parse(response.body)["error"]).to(eq("Invalid amount"))
    end

    it "returns 422 when amount is negative" do
      post "/withdraw", params: { amount: "-100" }, headers: headers

      expect(response).to(have_http_status(422))
      expect(JSON.parse(response.body)["error"]).to(eq("Invalid amount"))
    end

    it "returns 422 when withdrawing more than balance" do
      post "/withdraw", params: { amount: "20000" }, headers: headers

      expect(response).to(have_http_status(422))
      expect(JSON.parse(response.body)["error"]).to(include("failed"))
    end

    it "returns 401 without auth token" do
      post "/withdraw", params: { amount: "500" }

      expect(response).to(have_http_status(401))
    end
  end
end
