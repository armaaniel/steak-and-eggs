module Types
 class ConnectionsType < Types::BaseObject
   field(:id, ID, null:true)
   field(:subscriptions, [Types::SubscriptionsType], null:false)
   field(:started_at, GraphQL::Types::ISO8601DateTime, null:true)
   field(:user_agent, String, null:true)
   field(:connection_state, String, null:true)
 end
end