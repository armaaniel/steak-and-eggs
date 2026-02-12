module Types
  class QueryType < Types::BaseObject
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
    
    field(:connections, [Types::ConnectionsType], null:false) do
      description('fetch active connections')
    end
    
    field(:trace_stats, Types::TraceStatsType) do
      argument(:endpoint, String)
      description('fetch trace statistics')
    end
        
    def connections
      ActionCable.server.connections.map do |connection|
        {
          started_at: connection.instance_variable_get(:@started_at),
          connection_state: connection.instance_variable_get(:@websocket)&.alive?,
          subscriptions: connection.subscriptions.identifiers.map do |identifier| 
            JSON.parse(identifier, symbolize_names: true)
          end
        }
      end
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
        Trace.where("endpoint ILIKE ? AND endpoint NOT LIKE ?", route, 'GET /stocks/%/%')&.order(created_at: :desc)
      else
      Trace.where("endpoint ILIKE ?", route)&.order(created_at: :desc)
      end
    end
    
    def trace_stats(endpoint:)
      route = normalize_endpoint(endpoint)

      sql = if endpoint == 'GET /stocks/symbol'
        <<~SQL
          SELECT
            COUNT(*) as total_requests,
            PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY duration) as p50,
            PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration) as p95,
            PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration) as p99,
            COUNT(*) FILTER (WHERE status >= 400) as error_count
          FROM traces
          WHERE endpoint ILIKE '#{route}' AND endpoint NOT LIKE 'GET /stocks/%/%'
        SQL
      else
        <<~SQL
          SELECT
            COUNT(*) as total_requests,
            PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY duration) as p50,
            PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration) as p95,
            PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration) as p99,
            COUNT(*) FILTER (WHERE status >= 400) as error_count
          FROM traces
          WHERE endpoint ILIKE '#{route}'
        SQL
      end

      result = ActiveRecord::Base.connection.execute(sql).first

      {total_requests: result['total_requests'].to_i,
        p50: result['p50']&.to_f || 0.0,
        p95: result['p95']&.to_f || 0.0,
        p99: result['p99']&.to_f || 0.0,
        error_rate: result['total_requests'].to_i > 0 ? (result['error_count'].to_f / result['total_requests'].to_f * 100).round(2) : 0.0
      }
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
          WHEN endpoint LIKE 'GET /positions/%' THEN 'GET /positions/:symbol'
          WHEN endpoint LIKE 'GET /search%' THEN 'GET /search'
          WHEN endpoint LIKE 'GET /stocks/%/tickerdata' THEN 'GET /stocks/:symbol/tickerdata'
          WHEN endpoint LIKE 'GET /stocks/%/userdata' THEN 'GET /stocks/:symbol/userdata'
          WHEN endpoint LIKE 'GET /stocks/%/stockprice' THEN 'GET /stocks/:symbol/stockprice'
          WHEN endpoint LIKE 'POST /stocks/%/buy' THEN 'POST /stocks/:symbol/buy'
          WHEN endpoint LIKE 'POST /stocks/%/sell' THEN 'POST /stocks/:symbol/sell'
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
      when 'GET /search'
        'GET /search%'
      when 'GET /stocks/symbol/tickerdata'
        'GET /stocks/%/tickerdata'
      when 'GET /stocks/symbol/userdata'
        'GET /stocks/%/userdata'
      when 'GET /stocks/symbol/stockprice'
        'GET /stocks/%/stockprice'
      when 'POST /stocks/symbol/buy'
        'POST /stocks/%/buy'
      when 'POST /stocks/symbol/sell'
        'POST /stocks/%/sell'
      else
        endpoint
      end
    end  
  end
end
  