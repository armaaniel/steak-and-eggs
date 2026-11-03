require 'rails_helper'
require 'rake'

RSpec.describe("record") do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("record") }

  let(:user) { create(:user, balance: 1000) }

  def run
    task = Rake::Task["record"]
    task.reenable
    task.invoke
  end

  it("records each user's cash plus their positions at the live price") do
    Position.create!(user: user, symbol: "AAPL", shares: 2, average_price: 100)
    allow(REDIS).to(receive(:mget).with("price:AAPL").and_return(["150"]))

    run

    expect(PortfolioRecord.find_by(user: user).portfolio_value).to(eq(1300))
    expect(JobRun.last).to(have_attributes(name: "record", status: "succeeded"))
  end

  it("records a user with no positions without asking valkey") do
    user
    allow(REDIS).to(receive(:mget))

    run

    expect(PortfolioRecord.find_by(user: user).portfolio_value).to(eq(1000))
    expect(REDIS).not_to(have_received(:mget))
  end

  it("fails the run instead of recording cash only when valkey is down") do
    Position.create!(user: user, symbol: "AAPL", shares: 2, average_price: 100)
    allow(REDIS).to(receive(:mget).and_raise(Redis::CannotConnectError))

    expect { run }.to(raise_error(JobRun::PartialFailure, "1 batches and 0 users weren't recorded"))

    expect(PortfolioRecord.count).to(eq(0))
    expect(JobRun.last).to(have_attributes(error_class: "JobRun::PartialFailure", status: "failed"))
  end

  it("records everyone else, then fails the run, when one user can't be valued") do
    other = create(:user, balance: 500)
    Position.create!(user: user, symbol: "AAPL", shares: 2, average_price: 100)
    allow(REDIS).to(receive(:mget).with("price:AAPL").and_return(["not a price"]))

    expect { run }.to(raise_error(JobRun::PartialFailure, "0 batches and 1 users weren't recorded"))

    expect(PortfolioRecord.find_by(user: other).portfolio_value).to(eq(500))
    expect(PortfolioRecord.find_by(user: user)).to(be_nil)
    expect(JobRun.last.status).to(eq("failed"))
  end
end
