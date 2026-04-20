class UsersController < ApplicationController
  before_action(:verify_token, except: [:login, :signup, :demo])

  def login
    user = UserService.authenticate(username: params[:username], password: params[:password])

    if user
      token = JWT.encode({user_id: user.id}, Rails.application.secret_key_base, 'HS256')
      render(json: {token: token, username: user.username })
    else
      render(json: {error: 'Your email or password was incorrect. Please try again' }, status: 401)
    end

  rescue => e
    Sentry.capture_exception(e)
    render(json: {error: 'Something went wrong, please try again' }, status: 503)
  end

  def signup
    user = UserService.signup(username:params[:username], password:params[:password])

    token = JWT.encode({user_id: user.id}, Rails.application.secret_key_base, 'HS256')
    render(json: {token: token, username: user.username})

  rescue ActiveRecord::RecordInvalid => e
    render(json: {error: "Username has been taken, please choose another"}, status: 422)
  rescue => e
    Sentry.capture_exception(e)
    render(json: {error: "Something went wrong, please try again"}, status: 503)
  end

  def deposit
    amount = BigDecimal(params[:amount])
    return render(json: {error: "Invalid amount"}, status: 422) if params[:amount].nil? || amount <= 0

    UserService.deposit(amount:amount, user_id:@current_user.id)
    head(:ok)

  rescue => e
    Sentry.capture_exception(e)
    render(json: {error: 'Deposit failed, please try again'}, status: 422)
  end
  
  def withdraw
    amount = BigDecimal(params[:amount])
    return render(json: {error: "Invalid amount"}, status: 422) if params[:amount].nil? || amount <= 0

    UserService.withdraw(amount:amount, user_id:@current_user.id)
    head(:ok)

  rescue => e
    Sentry.capture_exception(e)
    render(json: {error: 'Withdraw failed, please retry'}, status: 422)
  end
  
  def change_password
    return render(json: {error: "new password is required"}, status: 422) if params[:new_password].nil?

    UserService.change_password(user_id: @current_user.id, new_password: params[:new_password])
    head(:ok)

  rescue => e
    Sentry.capture_exception(e)
    render(json: {error: 'Something went wrong, please try again'}, status: 503)
  end

  def delete_account
    UserService.delete_account(user_id: @current_user.id)
    head(:ok)

  rescue => e
    Sentry.capture_exception(e)
    render(json: {error: 'Something went wrong, please try again'}, status: 503)
  end
  
  def demo
    
    username = "demo_#{SecureRandom.hex(4)}"
    password = SecureRandom.hex(10)
    
    user = UserService.signup(username:username, password: password)
    UserService.seed_demo(user_id:user.id)
    
    token = JWT.encode({user_id: user.id}, Rails.application.secret_key_base, 'HS256')
    render(json: {token: token, username: user.username})
    
  rescue => e
    Sentry.capture_exception(e)
    render(json: {error: "Something went wrong, please try again"}, status: 503)
  end  
end
