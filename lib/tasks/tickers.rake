namespace :tickers do
  desc "Fetch common stock tickers from Polygon and upsert into the tickers table"
  task stocks: :environment do
    fetch_polygon_tickers("CS")
  end

  desc "Fetch ETF tickers from Polygon and upsert into the tickers table"
  task etfs: :environment do
    fetch_polygon_tickers("ETF")
  end

  desc "Fetch both stock and ETF tickers"
  task all: %i[stocks etfs]
end

def fetch_polygon_tickers(type)
  require "net/http"
  require "json"

  all_tickers = []
  url = "https://api.polygon.io/v3/reference/tickers?apikey=#{ENV['API_KEY']}&limit=1000&market=stocks&type=#{type}"

  while url
    puts "Fetching #{type}: #{url}"
    response = Net::HTTP.get_response(URI(url))

    unless response.code == "200"
      puts "Error: #{response.body}"
      break
    end

    data = JSON.parse(response.body)
    all_tickers += data["results"] if data["results"]

    url = data["next_url"] ? "#{data['next_url']}&apikey=#{ENV['API_KEY']}" : nil

    puts "Got #{data['results']&.length} #{type} (total: #{all_tickers.length})"
    sleep(0.1)
  end

  puts "Final total: #{all_tickers.length} #{type} tickers"

  ticker_attrs = all_tickers.map do |t|
    {
      symbol: t["ticker"],
      name: t["name"],
      ticker_type: t["type"],
      exchange: t["primary_exchange"],
      currency: t["currency_name"],
    }
  end.uniq { |t| t[:symbol] }

  puts "Removed #{all_tickers.length - ticker_attrs.length} duplicates"

  Ticker.upsert_all(ticker_attrs, unique_by: :symbol)
  puts "Upserted #{ticker_attrs.length} #{type} tickers"
end
