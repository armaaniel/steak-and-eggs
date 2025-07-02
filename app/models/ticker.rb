class Ticker < ApplicationRecord
  validates(:symbol, :name, :ticker_type, :exchange, :currency, presence: true)
  validates(:symbol, uniqueness: { case_sensitive: false })  
end
