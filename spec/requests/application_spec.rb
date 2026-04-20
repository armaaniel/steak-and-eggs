require 'rails_helper'

RSpec.describe("Authentication", type: :request) do
  let(:user) { create(:user) }

  describe "verify_token" do
    it "authenticates with valid JWT" do
      allow(RedisService).to(receive(:safe_get).and_return(nil))
      allow(RedisService).to(receive(:safe_setex))

      get "/portfoliodata", headers: auth_headers(user)

      expect(response).to(have_http_status(200))
    end

    it "returns 401 when token is missing" do
      get "/portfoliodata"

      expect(response).to(have_http_status(401))
      expect(JSON.parse(response.body)["error"]).to(eq("No Token"))
    end

    it "returns 401 when token is malformed" do
      get "/portfoliodata", headers: { "authToken" => "garbage.token.here" }

      expect(response).to(have_http_status(401))
      expect(JSON.parse(response.body)["error"]).to(eq("Authentication failed"))
    end

    it "returns 401 when token is signed with wrong secret" do
      token = JWT.encode({ user_id: user.id }, "wrong_secret", 'HS256')

      get "/portfoliodata", headers: { "authToken" => token }

      expect(response).to(have_http_status(401))
      expect(JSON.parse(response.body)["error"]).to(eq("Authentication failed"))
    end

    it "returns 401 when user no longer exists" do
      token = JWT.encode({ user_id: 99999 }, Rails.application.secret_key_base, 'HS256')

      get "/portfoliodata", headers: { "authToken" => token }

      expect(response).to(have_http_status(401))
    end
  end
end

RSpec.describe("Application", type: :request) do
  describe "GET /" do
    it "returns health check" do
      get "/"

      expect(response).to(have_http_status(200))

      body = JSON.parse(response.body)
      expect(body["status"]).to(eq("ok"))
      expect(body["time"]).to(be_present)
    end
  end

  describe "catch-all route" do
    it "returns 404 for unknown routes" do
      get "/nonexistent/route"

      expect(response).to(have_http_status(404))
      expect(JSON.parse(response.body)["error"]).to(eq("Not Found"))
    end
  end

  describe "POST /record" do
    let!(:user) { create(:user, balance: 5000) }

    before do
      allow(ENV).to(receive(:[]).and_call_original)
      allow(ENV).to(receive(:[]).with('GQL_KEY').and_return('test_secret'))
      allow(ENV).to(receive(:fetch).and_call_original)
      allow(RedisService).to(receive(:safe_get).and_return(nil))
      allow(RedisService).to(receive(:safe_setex))
      allow(RedisService).to(receive(:safe_del))
      allow(RedisService).to(receive(:safe_mget).and_return([]))
    end

    it "returns 200 and creates portfolio records with valid key" do
      post "/record", headers: { "Key" => "test_secret" }

      expect(response).to(have_http_status(200))

      record = PortfolioRecord.find_by(user_id: user.id, date: Date.current)
      expect(record).to(be_present)
    end

    it "returns 401 with invalid key" do
      post "/record", headers: { "Key" => "wrong_key" }

      expect(response).to(have_http_status(401))
    end

    it "returns 401 with no key" do
      post "/record"

      expect(response).to(have_http_status(401))
    end

    it "continues processing other users if one fails" do
      user2 = create(:user, balance: 3000)
      allow(PositionService).to(receive(:get_aum).with(user_id: user.id, balance: user.balance).and_raise(StandardError))
      allow(PositionService).to(receive(:get_aum).with(user_id: user2.id, balance: user2.balance).and_return({ aum: 3000 }))
      allow(Sentry).to(receive(:capture_exception))

      post "/record", headers: { "Key" => "test_secret" }

      expect(response).to(have_http_status(200))

      record = PortfolioRecord.find_by(user_id: user2.id, date: Date.current)
      expect(record).to(be_present)
      expect(record.portfolio_value).to(eq(3000))
    end

    it "invalidates portfolio cache for each user" do
      expect(RedisService).to(receive(:safe_del).with("portfolio:#{user.id}"))

      post "/record", headers: { "Key" => "test_secret" }
    end
  end
end
