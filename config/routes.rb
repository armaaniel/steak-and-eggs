Rails.application.routes.draw do
  post "/graphql", to: "graphql#execute"
  root("pages#index")
  get('login', to: 'pages#login')
  get('signup', to: 'pages#signup')
  post('signup', to: 'users#signup')
  post('login', to: 'users#login')
  get('home', to: 'home#home')
  post('balance', to:'users#update_balance')
  get('search', to:'home#search')
  get('stocks/:symbol', to:'stocks#show')
  post('position', to: 'stocks#position')
  get('logout', to: 'users#logout')
  get('activity', to: 'home#activity')
  
  get('positions/:symbol', to: 'positions#get_position')  
  
  get('stocks/:symbol/marketdata', to: 'stocks#get_market_data')
  get('stocks/:symbol/companydata', to: 'stocks#get_company_data')
  get('stocks/:symbol/chartdata', to: 'stocks#get_chart_data')
  
  match('*path', to: 'pages#not_found', via: :all)
  
  mount ActionCable.server => '/cable'
end
