module Types
  class QueryType < Types::BaseObject
    field(:users_by_username, [Types::UserType]) do 
      argument(:term, String, required: true)
      description('search users by username')
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
    
    field(:trace_summary, [Types::TraceSummaryType]) do
      description('fetch trace data by routes')
    end
    
    field(:trace_list, [Types::TraceType]) do
      argument(:endpoint, String)
      description('fetch trace list by route')
    end
    
    field(:trace_breakdown, Types::TraceBreakdownType) do
      argument(:endpoint, String)
      description('fetch trace list breakdown')
    end
    
    field(:latent_traces, [Types::TraceType]) do
      description('fetch most latent traces')
    end
    
    field(:most_requested_traces, [Types::TraceSummaryType]) do
      description('fetch most requested traces')
    end
        
    def users_by_username(term:)
      User.where("lower(username) LIKE ?", "%#{term.downcase}%").limit(5)
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
    
    def trace_breakdown(endpoint:)
      route = normalize_endpoint(endpoint)
      
      query = Trace.where("endpoint LIKE ?", route).where.not("breakdown::text = ? OR breakdown IS NULL", '{}')
      
      redis_query = query.where("breakdown::text LIKE ?", '%"used_redis":true%')&.order(created_at: :desc)
      db_api_query = query.where("breakdown::text LIKE ? OR breakdown::text LIKE ?", '%"used_api":true%', '%"used_db":true%')&.order(created_at: :desc)
      
      if redis_query.empty?
        redis_query = []
      end
      
      if db_api_query.empty?
        db_api_query = []
      end
      
      {redis_query: redis_query, db_api_query: db_api_query}
      
    end
    
    def trace_list(endpoint:)
      route = normalize_endpoint(endpoint)
      
      if endpoint == 'GET /stocks/symbol'
        Trace.where("endpoint LIKE ? AND endpoint NOT LIKE ?", route, 'GET /stocks/%/%')&.order(created_at: :desc)
      else
      Trace.where("endpoint LIKE ?", route)&.order(created_at: :desc)
      end
    end
    
    def latent_traces      
      Trace.all.order(duration: :desc).limit(1000)
    end
    
    def trace_summary
      sql = <<~SQL 
      SELECT
        CASE
          WHEN endpoint LIKE 'GET /stocks/%/marketdata' THEN 'GET /stocks/:symbol/marketdata'
          WHEN endpoint LIKE 'GET /stocks/%/companydata' THEN 'GET /stocks/:symbol/companydata'
          WHEN endpoint LIKE 'GET /stocks/%/chartdata' THEN 'GET /stocks/:symbol/chartdata'
          WHEN endpoint LIKE 'GET /stocks/%' THEN 'GET /stocks/:symbol'
          WHEN endpoint LIKE 'GET /positions/%' THEN 'GET /positions/:symbol'
          WHEN endpoint LIKE 'GET /search%' THEN 'GET /search'
          ELSE endpoint
        END as route,
        COUNT(*) as total_requests,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration) as p99
      FROM traces 
      GROUP BY route
      ORDER BY total_requests DESC  
    SQL
    
    results = ActiveRecord::Base.connection.execute(sql)
    
    typed_results = results.map do |row|
      
        {
          route: row['route'],
          clean_route: row['route'].downcase.gsub(' ','').gsub(':',''),
          total_requests: row['total_requests'].to_i,
          p99: row['p99']&.to_f || 0.0
        }  
      end
    end
    
    def most_requested_traces
      sql = <<~SQL 
          SELECT
            endpoint,
            COUNT(*) as total_requests,
            PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration) as p99
          FROM traces 
          GROUP BY endpoint
          ORDER BY total_requests DESC
          LIMIT 100
        SQL
  
        results = ActiveRecord::Base.connection.execute(sql)
  
        results.map do |row|
          {
            route: row['endpoint'],
            clean_route: row['endpoint'].gsub(' ','').gsub(':',''),
            total_requests: row['total_requests'].to_i,
            p99: row['p99']&.to_f || 0.0
          }
        end
      end
    
    private
    
    def normalize_endpoint(endpoint)
      case endpoint
      when 'GET /stocks/symbol/marketdata'
        'GET /stocks/%/marketdata'
      when 'GET /stocks/symbol/companydata'
        'GET /stocks/%/companydata'
      when 'GET /stocks/symbol/chartdata'
        'GET /stocks/%/chartdata'
      when 'GET /stocks/symbol'
        'GET /stocks/%'
      when 'GET /positions/symbol'
        'GET /positions/%'
      when 'GET /search'
        'GET /search%'
      else
        endpoint
      end
    end  
  end
end
  