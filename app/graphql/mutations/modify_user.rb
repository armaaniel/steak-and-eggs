module Mutations
  class ModifyUser < BaseMutation
    argument(:first_name, String, required:true)
    argument(:middle_name, String, required:false)
    argument(:last_name, String, required:true)
    argument(:email, String, required:true)
    argument(:date_of_birth, GraphQL::Types::ISO8601Date, required:true)
    argument(:gender, String, required:true)
    argument(:balance, Float, required:true)

    field(:user, Types::UserType, null:true)
    field(:errors, [String], null:false)

    def resolve(first_name:, middle_name:, last_name:, email:, balance:, gender:, date_of_birth:)
      user = User.find_by(email: email)

      user.update(first_name: first_name, middle_name: middle_name, last_name: last_name, email: email, date_of_birth: date_of_birth,
      gender: gender, balance: balance)

      if user.save
        {user: user, errors: []}
      else
        {user: nil, errors: user.errors.full_messages}
      end
    end
  end
end
