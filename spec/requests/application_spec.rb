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

end
