module Mutations
  class CreateUser < BaseMutation
    argument(:first_name, String, required:true)
    argument(:middle_name, String, required:false)
    argument(:last_name, String, required:true)
    argument(:email, String, required:true)
    argument(:password, String, required:true)
    argument(:date_of_birth, GraphQL::Types::ISO8601Date, required:true)
    argument(:gender, String, required:true)

    field(:user, Types::UserType, null:true)
    field(:errors, [String], null:false)

    def resolve(first_name:, middle_name:, last_name:, email:, password:, date_of_birth:, gender:)
      user = User.new(first_name: first_name, middle_name: middle_name, last_name: last_name, email: email, password: password,
      gender: gender, date_of_birth:date_of_birth )

      if user.save
        {user: user, errors: []}
      else
        {user: nil, errors: user.errors.full_messages}
      end
    end
  end
end
