class PagesController < ApplicationController
  def index
  end
  def login
    if session[:user_id]
      redirect_to home_path
    end
  end
  def signup
    if session[:user_id]
      redirect_to home_path
    end
  end
end
