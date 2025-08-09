Rails.application.routes.draw do
  post "/graphql", to: "graphql#execute"  
  post('login', to: 'users#login')
  post('signup', to: 'users#signup')
  post('deposit', to: 'users#deposit')
  post('withdraw', to: 'users#withdraw')
  
  get('search', to: 'home#search')
  get('portfoliochart', to: 'home#get_portfolio_chart_data')
  get('portfoliodata', to: 'home#get_portfolio_data')
  get('verifytoken', to: 'api#verify_token')
  get('activitydata', to: 'home#get_activity_data')
 
  constraints(symbol: /[^\/]+/) do 
  get('stocks/:symbol/tickerdata', to: 'stocks#get_ticker_data')
  get('stocks/:symbol/chartdata', to: 'stocks#get_chart_data')
  get('stocks/:symbol/userdata', to: 'stocks#get_user_data')
  get('stocks/:symbol/companydata', to: 'stocks#get_company_data')
  get('stocks/:symbol/marketdata', to: 'stocks#get_market_data')
  get('stocks/:symbol/stockprice', to: 'stocks#get_stock_price')
  post('stocks/:symbol/buy', to: 'stocks#buy')
  post('stocks/:symbol/sell', to: 'stocks#sell')
end
  
  mount ActionCable.server => '/cable'
end
