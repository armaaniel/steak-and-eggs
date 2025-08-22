module Types
 class SubscriptionsType < Types::BaseObject
   field(:channel, String, null:false)
   field(:symbol, String,  null:false)
 end
end