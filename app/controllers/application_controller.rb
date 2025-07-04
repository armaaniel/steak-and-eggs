class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  helper_method(:current_user) 
  
  def authenticate_user
    if session[:user_id].nil?
      redirect_to login_path  
    end
  end
  
  private
  
  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  rescue => e
  end       
end