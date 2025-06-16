module Types
  class QueryType < Types::BaseObject
    field(:users_by_email_or_name, [Types::UserType]) do 
      argument(:term, String, required: true)
      description('search users by email or name')
    end
    
    field(:users_by_id, Types::UserType) do
      argument(:id, ID, required:true)
      description('fetch user data by ID')
    end
    
    field(:positions, Types::PositionsType) do
      argument(:id, ID, required:true)
      description('fetch position data by user id')
    end
    
    field(:transactions, [Types::TransactionsType]) do
      argument(:id, ID, required:true)
      description('fetch transaction data by user id')
    end
    
    field(:margin_call_status, [Types::UserType]) do
      description('fetch users by margin call status')
    end 
        
    def users_by_email_or_name(term:)
      User.where("lower(email) LIKE ? OR lower(first_name) LIKE ?", "%#{term.downcase}%", "%#{term.downcase}%").limit(5)
    end
    
    def users_by_id(id:)
      User.find_by(id: id)
    end
    
    def positions(id:)
      Position.where(user_id: id)
    end
    
    def transactions(id:)
      Transaction.where(user_id: id)
    end
    
    def margin_call_status
      User.where(margin_call_status: 'active')
    end
    
end
end
  