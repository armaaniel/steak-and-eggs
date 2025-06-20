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
  get('aum', to: 'portfolio#aum')
  get('bpm', to: 'portfolio#buying_power_margin')
  get('positions', to: 'portfolio#positions')
  match('*path', to: 'pages#not_found', via: :all)
  
  mount ActionCable.server => '/cable'
end
