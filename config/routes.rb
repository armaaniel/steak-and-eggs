Rails.application.routes.draw do
  root("pages#index")
  get('login', to: 'pages#login')
  get('signup', to: 'pages#signup')
  post('users', to: 'users#create')
  post('login', to: 'users#login')
  get('home', to: 'home#home')
  post('balance', to:'users#update_balance')
  get('search', to:'home#search')
  get('stocks/:symbol', to:'stocks#show')
  post('position', to: 'stocks#position')
  get('logout', to: 'users#logout')
end
