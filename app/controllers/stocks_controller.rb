class StocksController < ApplicationController
  before_action(:authenticate_user)
  before_action(:get_data)
  layout 'authenticated'
  def show
  end
    
  def position
    case params[:commit]
    when 'buy'
      return if !params[:quantity].present?
      params[:quantity] = params[:quantity].to_i 
      if current_user.balance >= (params[:quantity] * @marketdata.price.to_i)
        current_user.balance -= (params[:quantity] * @marketdata.price.to_i)
        current_user.save
        if @record
          @record.update(shares: (params[:quantity] + @record[:shares]))
        else
          Position.create(user_id: current_user.id, symbol: params[:symbol], shares: params[:quantity])
        end
        Transaction.create(quantity: params[:quantity], amount: (params[:quantity] * @marketdata.price.to_i), transaction_type: 'Buy', user_id: current_user.id)
      end
      
    when 'sell'
      return if !params[:quantity].present? || @record.nil?
      params[:quantity] = params[:quantity].to_i 
      if @record[:shares] == params[:quantity]
        current_user.balance += (params[:quantity] * @marketdata.price.to_i)
        current_user.save
        @record.delete()
      elsif @record[:shares] > params[:quantity]
        current_user.balance += (params[:quantity] * @marketdata.price.to_i)
        current_user.save
        @record.update(shares: (@record[:shares] - params[:quantity]))
      end
      Transaction.create(quantity: params[:quantity], amount: (params[:quantity] * @marketdata.price.to_i), transaction_type: 'Sell', user_id: current_user.id)
    end
    redirect_to "/stocks/#{params[:symbol]}"
  end
  
  private
  
  def get_data
    stock_object ||= Alphavantage::TimeSeries.new(symbol: params[:symbol])
    @marketdata = stock_object.quote
    @companydata = Alphavantage::Fundamental.new(symbol: params[:symbol]).overview
    @record = Position.find_by(user_id: current_user.id, symbol: params[:symbol])
    @daily = []
    stock_object&.daily['time_series_daily']&.each do |date, values|
      @daily.unshift({
        date: date,
        close: values['close'].to_f,
      })
    end
  end
  
end  
