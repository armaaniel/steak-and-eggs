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

RSpec.describe("Request errors", type: :request) do
  let(:user) { create(:user) }

  def request_payload
    payloads = []
    record = ->(*, payload) { payloads << payload }
    ActiveSupport::Notifications.subscribed(record, "process_action.action_controller") { yield }
    payloads.last
  end

  it "records the class, location and sentry event of a reported error" do
    allow(RedisService).to(receive(:safe_get).and_return(nil))
    allow(Sentry).to(receive(:capture_exception).and_return(instance_double(Sentry::ErrorEvent, event_id: "abc123")))

    payload = request_payload { post "/stocks/TSLA/buy", params: { quantity: 1 }, headers: auth_headers(user) }

    expect(response).to(have_http_status(503))
    expect(payload).to(include(error_class: "StandardError", sentry_event_id: "abc123"))
    expect(payload[:error_location]).to(start_with("app/services/market_service.rb"))
  end

  it "records an expected error without reporting it to sentry" do
    allow(MarketService).to(receive(:chartdata).and_raise(MarketService::NotFoundError))
    expect(Sentry).not_to(receive(:capture_exception))

    payload = request_payload { get "/stocks/ZZZZ/chartdata", headers: auth_headers(user) }

    expect(response).to(have_http_status(404))
    expect(payload).to(include(error_class: "MarketService::NotFoundError", sentry_event_id: nil))
  end

  it "records errors rescued in verify_token" do
    allow(Sentry).to(receive(:capture_exception))

    token = JWT.encode({ user_id: user.id }, "wrong_secret", 'HS256')

    payload = request_payload { get "/portfoliodata", headers: { "authToken" => token } }

    expect(response).to(have_http_status(401))
    expect(payload[:error_class]).to(eq("JWT::VerificationError"))
    expect(payload[:error_location]).to(start_with("app/controllers/application_controller.rb"))
  end

  it "adds no error fields to a successful request" do
    allow(RedisService).to(receive(:safe_get).and_return(nil))
    allow(RedisService).to(receive(:safe_setex))

    payload = request_payload { get "/search", params: { q: "TSL" } }

    expect(response).to(have_http_status(200))
    expect(payload.keys).not_to(include(:error_class, :error_location, :sentry_event_id))
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
