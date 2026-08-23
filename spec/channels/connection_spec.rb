require 'rails_helper'

RSpec.describe(ApplicationCable::Connection, type: :channel) do
  it "connects without a token" do
    expect {
      connect "/cable"
    }.not_to(raise_error)
  end

  it "connects with an invalid token" do
    expect {
      connect "/cable?token=garbage.token.here"
    }.not_to(raise_error)
  end
end
