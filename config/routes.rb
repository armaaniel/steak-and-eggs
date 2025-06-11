Rails.application.routes.draw do
  if Rails.env.development?
    mount GraphiQL::Rails::Engine, at: "/graphiql", graphql_path: "/graphql"
  end
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
  
  mount ActionCable.server => '/cable'
end
