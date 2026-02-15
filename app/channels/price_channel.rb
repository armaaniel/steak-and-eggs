class PriceChannel < ApplicationCable::Channel
  def subscribed
    stream_from("price_channel:#{params[:symbol]}")
  end

  def unsubscribed
    stop_all_streams
  end
end
