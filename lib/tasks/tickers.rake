require "net/http"
require "json"

namespace :tickers do
  desc "Sync tickers with Polygon: upsert the active ones and mark the rest delisted. DRY_RUN=1 previews"
  task sync: :environment do
    fetched = %w[CS ETF ETV ADRC UNIT FUND].flat_map { |type| fetch_polygon_tickers(type) }.uniq { |t| t[:symbol] }
    symbols = fetched.map { |t| t[:symbol] }
    complete, incomplete = fetched.partition { |t| t.values.all?(&:present?) }

    listed = Ticker.where(delisted_at: nil)
    missing = listed.where.not(symbol: symbols).pluck(:symbol).sort
    returning = Ticker.where.not(delisted_at: nil).where(symbol: symbols).count

    puts "Polygon lists #{fetched.size} active tickers; #{missing.size} of #{listed.count} listed here are gone, #{returning} come back"
    puts "Gone: #{missing.join(', ')}" if missing.any?
    puts "Skipping #{incomplete.size} with missing fields: #{incomplete.map { |t| t[:symbol] }.join(', ')}" if incomplete.any?
    next puts("Dry run, nothing written") if ENV["DRY_RUN"].present?

    ActiveRecord::Base.transaction do
      Ticker.upsert_all(complete.map { |t| t.merge(delisted_at: nil) }, unique_by: :symbol)
      Ticker.where(symbol: missing).update_all(delisted_at: Time.current)
    end

    cleared = RedisService.safe_delete_matching("search:*")
    puts "Upserted #{complete.size}, marked #{missing.size} delisted, cleared #{cleared || 0} cached searches"
  end
end

def fetch_polygon_tickers(type)
  tickers = []
  url = "https://api.polygon.io/v3/reference/tickers?limit=1000&market=stocks&type=#{type}"

  while url
    response = Net::HTTP.get_response(URI("#{url}&apikey=#{ENV['API_KEY']}"))
    raise "Polygon returned #{response.code} fetching #{type} tickers" unless response.code == "200"

    data = JSON.parse(response.body)
    tickers.concat(data["results"] || [])
    url = data["next_url"]
    sleep(0.1) if url
  end

  puts "Fetched #{tickers.size} #{type} tickers"

  tickers.map do |t|
    {symbol: t["ticker"], name: t["name"], ticker_type: t["type"], exchange: t["primary_exchange"], currency: t["currency_name"]}
  end
end
