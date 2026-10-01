require 'rails_helper'
require 'rake'

RSpec.describe("tickers:sync") do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("tickers:sync") }

  let(:listed) { (1..40).map { |i| format("T%03d", i) } }

  before do
    Ticker.insert_all((listed + ["TSE"]).map { |symbol| ticker(symbol) })
    allow(RedisService).to(receive(:safe_delete_matching).and_return(3))
    allow(ENV).to(receive(:[]).and_call_original)
  end

  def ticker(symbol)
    {symbol: symbol, name: "#{symbol} Inc", ticker_type: "CS", exchange: "XNYS", currency: "usd"}
  end

  def stub_polygon(common, failing_type: nil)
    allow(Net::HTTP).to(receive(:get_response)) do |uri|
      type = uri.to_s[/type=(\w+)/, 1]
      next instance_double(Net::HTTPResponse, code: "500") if type == failing_type

      results = type == "CS" ? common.map { |s| {ticker: s, name: "#{s} Inc", type: "CS", primary_exchange: "XNYS", currency_name: "usd"} } : []
      instance_double(Net::HTTPResponse, code: "200", body: {results: results}.to_json)
    end
  end

  def with_env(values)
    values.each { |key, value| allow(ENV).to(receive(:[]).with(key).and_return(value)) }
  end

  def run
    task = Rake::Task["tickers:sync"]
    task.reenable
    expect { task.invoke }.to(output.to_stdout)
  end

  def delisted
    Ticker.where.not(delisted_at: nil).pluck(:symbol)
  end

  it("marks tickers Polygon no longer lists, keeps the rest and adds new ones") do
    stub_polygon(listed + ["NEWCO"])

    run

    expect(delisted).to(eq(["TSE"]))
    expect(Ticker.find_by(symbol: "NEWCO").delisted_at).to(be_nil)
    expect(RedisService).to(have_received(:safe_delete_matching).with("search:*"))
  end

  it("brings a delisted ticker back when Polygon lists it again") do
    Ticker.where(symbol: "TSE").update_all(delisted_at: 1.day.ago)
    stub_polygon(listed + ["TSE"])

    run

    expect(delisted).to(eq([]))
  end

  it("writes nothing when any page fails, so a partial list never reads as delistings") do
    stub_polygon(listed + ["NEWCO"], failing_type: "ETF")
    task = Rake::Task["tickers:sync"]
    task.reenable

    expect { expect { task.invoke }.to(output.to_stdout) }.to(raise_error(RuntimeError, /Polygon returned 500 fetching ETF/))
    expect(delisted).to(eq([]))
    expect(Ticker.find_by(symbol: "NEWCO")).to(be_nil)
  end

  it("marks every ticker Polygon dropped in one run, however many") do
    stub_polygon(listed.first(30))

    run

    expect(delisted.size).to(eq(11))
  end

  it("only prints what it would do on a dry run") do
    stub_polygon(listed)
    with_env("DRY_RUN" => "1")
    task = Rake::Task["tickers:sync"]
    task.reenable

    expect { task.invoke }.to(output(/Gone: TSE.*Dry run, nothing written/m).to_stdout)
    expect(delisted).to(eq([]))
    expect(RedisService).not_to(have_received(:safe_delete_matching))
  end
end
