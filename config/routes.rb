Rails.application.routes.draw do
  post "/graphql", to: "graphql#execute"  
  post('logintwo', to: 'users_api#logintwo')
  post('signuptwo', to: 'users_api#signuptwo')
  post('deposit', to: 'users_api#deposit')
  post('withdraw', to: 'users_api#withdraw')
  
  get('searchtwo', to: 'home_api#searchtwo')
  get('portfoliochart', to: 'home_api#get_portfolio_chart_data')
  get('portfoliodata', to: 'home_api#get_portfolio_data')
  get('verifytoken', to: 'api#verify_token')
  get('activitydata', to: 'home_api#get_activity_data')
 
  constraints(symbol: /[^\/]+/) do 
  get('stocks/:symbol/tickerdata', to: 'stocks_api#get_ticker_data')
  get('stocks/:symbol/chartdatatwo', to: 'stocks_api#get_chart_data')
  get('stocks/:symbol/userdata', to: 'stocks_api#get_user_data')
  get('stocks/:symbol/companydatatwo', to: 'stocks_api#get_company_data')
  get('stocks/:symbol/marketdatatwo', to: 'stocks_api#get_market_data')
  get('stocks/:symbol/stockprice', to: 'stocks_api#get_stock_price')
  post('stocks/:symbol/buy', to: 'stocks_api#buy')
  post('stocks/:symbol/sell', to: 'stocks_api#sell')
end
  
  
    
  get('stocks/:symbol/marketdata', to: 'stocks#get_market_data')
  get('stocks/:symbol/companydata', to: 'stocks#get_company_data')
  get('stocks/:symbol/chartdata', to: 'stocks#get_chart_data')
    
  mount ActionCable.server => '/cable'
end
