Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins("http://localhost:5173", "http://localhost:5174", "https://steakneggs.app", "http://localhost:8081")
    resource "*",
    headers: :any,
    methods: [:get, :post, :put, :patch, :delete, :options, :head]
  end
end
