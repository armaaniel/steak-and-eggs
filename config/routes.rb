Rails.application.routes.draw do
  post "/graphql", to: "graphql#execute"
  post('login', to: 'users#login')
  post('signup', to: 'users#signup')
  post('deposit', to: 'users#deposit')
  post('withdraw', to: 'users#withdraw')
  post('change_password', to: 'users#change_password')
  delete('delete_account', to: 'users#delete_account')
  post('demo', to: 'users#demo')

  get('search', to: 'home#search')
  get('portfoliochart', to: 'home#get_portfolio_chart_data')
  get('portfoliodata', to: 'home#get_portfolio_data')
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

  post('/record', to: 'system#record')
  get('/', to: 'system#health')
  mount ActionCable.server => '/cable'
  match '*path', to: 'system#not_found', via: :all
end
