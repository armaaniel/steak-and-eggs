Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    if Rails.env.development?
      origins("http://localhost:5173", "http://localhost:5174")
    else
      origins("https://steakneggs.app")
    end
    resource "*",
    headers: :any,
    methods: [:get, :post, :put, :patch, :delete, :options, :head]       
  end
end
