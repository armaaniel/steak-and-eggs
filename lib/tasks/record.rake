task record: :environment do
  User.in_batches(of: 1000) do |batch|
    users = batch.index_by { |user| user.id }
    user_ids = users.keys

    all_positions = Position.where(user_id: user_ids).select(:user_id, :symbol, :shares)
    
    positions_by_user = all_positions.group_by { |position| position.user_id }
    
    all_symbols = positions_by_user.values.flatten.map { |position| position.symbol }.uniq

    all_prices = RedisService.safe_mget(*all_symbols.map { |symbol| "price:#{symbol}" })
    price_hash = all_symbols.zip(all_prices).to_h

    records = user_ids.map do |user_id|

      positions = positions_by_user[user_id] || []
      balance = users[user_id].balance
      
      aum = positions.inject(balance) do |acc, position|
        price = BigDecimal(price_hash[position.symbol] || "0")
        acc + (price * position.shares)
      end
      
      { user_id: user_id, date: Date.current, portfolio_value: aum }
      
    rescue => e
      Sentry.capture_exception(e)
      nil
    end.compact
    
    PortfolioRecord.upsert_all(records, unique_by: [:user_id, :date])
    RedisService.safe_del(*user_ids.map { |id| "portfolio:#{id}" })
  rescue => e
    Sentry.capture_exception(e)
  end
end