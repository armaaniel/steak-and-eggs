class PortfolioChannel < ApplicationCable::Channel
  def subscribed
    stream_from("portfolio_channel:#{user.id}")
  end
  
  def unsubscribed
    stop_all_streams
  end
end
