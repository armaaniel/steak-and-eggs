class HomeController < ApplicationController
  before_action(:authenticate_user)
  before_action(:daily)
  layout "authenticated"
  
  def home
    @positions = PositionService.positions(current_user: current_user)
  end

  def search
    @results = MarketService.search(search_key: params[:search])
  end
  
  def activity
    @activity = PositionService.transactions(current_user: current_user)
  end
  
  def daily
    daily = []
    stock_object = Alphavantage::TimeSeries.new(symbol: 'tsla')
    stock_object&.daily['time_series_daily']&.each do |date, values|
      daily.unshift({
        date: date,
        close: values['close'].to_f,
      })
    end
    @daily = daily
  end
  
end