class PagesController < ApplicationController
  def index
  end
  
  def login
    if session[:user_id]
      redirect_to home_path
    else
    render layout: 'login-signup'
  end
end

  def signup
    if session[:user_id]
      redirect_to home_path
    else
    render layout: 'login-signup'
  end
end

def not_found
  if session[:user_id]
    render layout: 'auth404'
  else
    render layout: 'application'
  end
end

end
