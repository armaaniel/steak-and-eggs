class UsersController < ApiController
  before_action(:verify_token, except: [:login, :signup])

  def login
    user = UserService.authenticate(username: params[:username], password: params[:password])

    if user
      payload = {user_id: user.id}
      token = JWT.encode(payload, Rails.application.secret_key_base, 'HS256')
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

    if user
      payload = {user_id: user.id}
      token = JWT.encode(payload, Rails.application.secret_key_base, 'HS256')
      render(json: {token: token, username: user.username})
    end

  rescue ActiveRecord::RecordInvalid => e
    render(json: {error: "Username has been taken, please choose another"}, status: 422)
  rescue => e
    Sentry.capture_exception(e)
    render(json: {error: "Something went wrong, please try again"}, status: 503)
  end

  def deposit
    amount = BigDecimal(params[:amount])
    return render(json: {error: "Invalid amount"}, status: 422) if params[:amount].nil? || amount <= 0

    result = UserService.deposit(amount:amount, user_id:@current_user.id)
    head(:ok)

  rescue => e
    Sentry.capture_exception(e)
    render(json: {error: 'Deposit failed, please try again'}, status: 422)
  end

  def delete_account
    return render(json: {error: "password is required"}, status: 422) if params[:password].nil?

    UserService.delete_account(user_id: @current_user.id, password: params[:password])
    head(:ok)

  rescue StandardError => e
    render(json: {error: 'Password is incorrect'}, status: 422)
  rescue => e
    Sentry.capture_exception(e)
    render(json: {error: 'Something went wrong, please try again'}, status: 503)
  end

  def change_password
    return render(json: {error: "current password and new password are required"}, status: 422) if params[:current_password].nil? || params[:new_password].nil?

    UserService.change_password(user_id: @current_user.id, current_password: params[:current_password], new_password: params[:new_password])
    head(:ok)

  rescue StandardError => e
    render(json: {error: 'Current password is incorrect'}, status: 422)
  rescue => e
    Sentry.capture_exception(e)
    render(json: {error: 'Something went wrong, please try again'}, status: 503)
  end

  def withdraw
    amount = BigDecimal(params[:amount])
    return render(json: {error: "Invalid amount"}, status: 422) if params[:amount].nil? || amount <= 0

    result = UserService.withdraw(amount:amount, user_id:@current_user.id)
    head(:ok)

  rescue => e
    Sentry.capture_exception(e)
    render(json: {error: 'Withdraw failed, please retry'}, status: 422)
  end
end
