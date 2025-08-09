module Types
  class UserType < Types::BaseObject
    field(:id, ID)
    field(:username, String)
    field(:balance, Float)
    field(:margin_call_status, String)
    field(:positions, [Types::PositionsType])
    field(:equity_ratio, Float)
    
    def equity_ratio
      PositionService.get_buying_power(user_id:object.id,balance:object.balance,used_margin:object.used_margin)&.dig(:equity_ratio)
    rescue => e
      Sentry.capture_exception(e)
      nil
    end
    
  end
end

    