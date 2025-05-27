# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    field(:create_user, mutation: Mutations::CreateUser)
    field(:modify_user, mutation: Mutations::ModifyUser)
  end
end
