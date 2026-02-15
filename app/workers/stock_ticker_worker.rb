class StockTickerWorker
  include Sidekiq::Worker

  def perform
    require 'net/http'
    require 'json'

    all_tickers = []
    url = "https://api.polygon.io/v3/reference/tickers?apikey=#{ENV['API_KEY']}&limit=1000&market=stocks&type=CS"

    while url
      puts "Fetching: #{url}"
      response = Net::HTTP.get_response(URI(url))

      if response.code == "200"
        data = JSON.parse(response.body)
        all_tickers += data['results'] if data['results']

        if data['next_url']
          url = "#{data['next_url']}&apikey=#{ENV['API_KEY']}"
        else
          url = nil
        end

        puts "Got #{data['results']&.length} tickers (total: #{all_tickers.length})"
        sleep(0.1)
      else
        puts "Error: #{response.body}"
        break
      end
    end

    puts "Final total: #{all_tickers.length} tickers"

    ticker_transformed = all_tickers.map do |n|
      {
        symbol: n['ticker'],
        name: n['name'],
        ticker_type: n['type'],
        exchange: n['primary_exchange'],
        currency: n['currency_name']
      }
    end

    unique_tickers = ticker_transformed.uniq { |ticker| ticker[:symbol] }

    puts "Removed #{ticker_transformed.length - unique_tickers.length} duplicates"

    Ticker.upsert_all(unique_tickers, unique_by: :symbol)
  end
end
