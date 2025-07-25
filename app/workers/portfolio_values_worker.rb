class PortfolioValuesWorker
  include Sidekiq::Worker
  
  def perform
    
    connected_users = REDIS.smembers("connected_users").map {|n| n.to_i}
    puts "Connected users: #{connected_users}"
    
    return if connected_users.empty?
    
    all_positions = Position.where(user_id:connected_users)
    all_users = User.where(id: connected_users).index_by { |n| n.id}
      
    all_symbols = all_positions.pluck(:symbol).uniq
    
    price_keys = all_symbols.map {|symbol| "price:#{symbol}"}
    
    price_values = REDIS.mget(*price_keys)
    
    prices = all_symbols.zip(price_values).to_h
    
    positions_by_user = all_positions.group_by {|n| n.user_id}
    
    positions_by_user.each do |id, positions|
      stock_value = 0
      user_prices = {}
      positions.each do |position|
        stock_value += position.shares * prices[position.symbol]&.to_f
        user_prices[position.symbol] = prices[position.symbol]&.to_f
      end
      
      cash_balance = all_users[id].balance
      used_margin = all_users[id].used_margin
      
      portfolio_value = stock_value + cash_balance
      equity = portfolio_value - used_margin
      
      available_margin = (equity * 0.5) - used_margin
      buying_power = cash_balance + available_margin
      
      
      ActionCable.server.broadcast("portfolio_channel:#{id}", {portfolio_value: portfolio_value, stock_prices: user_prices,
        buying_power:buying_power, available_margin:available_margin, cash_balance:cash_balance})
    end
  end
end

    
    
    
    