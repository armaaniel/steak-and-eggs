module Types
 class ConnectionsType < Types::BaseObject
   field(:subscriptions, [Types::SubscriptionsType], null:false)
   field(:started_at, GraphQL::Types::ISO8601DateTime, null:true)
   field(:connection_state, String, null:true)
 end
end