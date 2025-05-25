module Types
  class UserType < Types::BaseObject
    field(:id, ID)
    field(:email, String)
    field(:balance, Float)
    field(:first_name, String)
    field(:middle_name, String)
    field(:last_name, String)
    field(:date_of_birth, String)
    field(:gender, Types::GenderEnumType)
    field(:positions, [Types::PositionsType])
  end
end

    