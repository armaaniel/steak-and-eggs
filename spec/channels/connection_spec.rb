require 'rails_helper'

RSpec.describe(ApplicationCable::Connection, type: :channel) do
  let(:user) { create(:user) }

  it "connects with valid JWT" do
    token = JWT.encode({ user_id: user.id }, Rails.application.secret_key_base, 'HS256')

    connect "/cable?token=#{token}"

    expect(connection.user).to(eq(user))
  end

  it "rejects connection without token" do
    expect {
      connect "/cable"
    }.to(have_rejected_connection)
  end

  it "rejects connection with invalid token" do
    expect {
      connect "/cable?token=garbage.token.here"
    }.to(have_rejected_connection)
  end

  it "rejects connection with wrong secret" do
    token = JWT.encode({ user_id: user.id }, "wrong_secret", 'HS256')

    expect {
      connect "/cable?token=#{token}"
    }.to(have_rejected_connection)
  end

  it "rejects connection when user does not exist" do
    token = JWT.encode({ user_id: 99999 }, Rails.application.secret_key_base, 'HS256')

    expect {
      connect "/cable?token=#{token}"
    }.to(have_rejected_connection)
  end
end