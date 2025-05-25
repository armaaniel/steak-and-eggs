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
    
    field(:users_with_positions_by_id, Types::UserType) do
      argument(:id, ID, required:true)
      description('fetch user data with positions by ID')
    end
    
    field(:positions, Types::PositionsType) do
      argument(:id, ID, required:true)
      description('fetch position data by user id')
    end
        
    def users_by_email_or_name(term:)
      User.where("lower(email) LIKE ? OR lower(first_name) LIKE ?", "%#{term.downcase}%", "%#{term.downcase}%").limit(5)
    end
    
    def users_by_id(id:)
      User.find_by(id: id)
    end
    
    def users_with_positions_by_id(id:)
      User.find_by(id: id)
    end
    
    def positions(id:)
      Position.where(user_id: id)
    end
    
  end
end
  