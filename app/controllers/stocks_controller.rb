class StocksController < ApplicationController
  before_action(:authenticate_user)
  before_action(:set_price_and_record)
  layout 'authenticated'
  def show
  end
    
  def position
    case params[:commit]
    when 'buy'
      return if !params[:quantity].present?
      params[:quantity] = params[:quantity].to_i 
      if current_user.balance >= (params[:quantity] * @price)
        current_user.balance -= (params[:quantity] * @price)
        current_user.save
        if @record
          @record.update(shares: (params[:quantity] + @record[:shares]))
        else
          Position.create(user_id: current_user.id, symbol: params[:symbol], shares: params[:quantity])
        end
      end
      
    when 'sell'
      return if !params[:quantity].present? || @record.nil?
      params[:quantity] = params[:quantity].to_i 
      if @record[:shares] == params[:quantity]
        current_user.balance += (params[:quantity] * @price)
        current_user.save
        @record.delete()
      elsif @record[:shares] > params[:quantity]
        current_user.balance += (params[:quantity] * @price)
        current_user.save
        @record.update(shares: (@record[:shares] - params[:quantity]))
      end
    end
    
  end
  
  private
  
  def set_price_and_record
    finnhub_client ||= FinnhubRuby::DefaultApi.new
    @price = finnhub_client.quote(params[:symbol]).c
    @record = Position.find_by(user_id: current_user.id, symbol: params[:symbol])
  end
  
end  
