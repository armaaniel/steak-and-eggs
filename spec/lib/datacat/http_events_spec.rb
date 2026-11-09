require 'rails_helper'
require 'socket'

RSpec.describe(Datacat::HttpEvents) do
  let(:http_class) { Class.new(Net::HTTP) { prepend Datacat::HttpEvents } }
  let(:server) { TCPServer.new('127.0.0.1', 0) }
  let(:port) { server.addr[1] }

  around do |example|
    responder = Thread.new do
      loop do
        client = server.accept
        while (line = client.gets) && line != "\r\n"; end
        client.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
        client.close
      end
    end
    example.run
  ensure
    responder.kill
    server.close
  end

  def announced(&)
    events = []
    callback = ->(name, _start, _finish, _id, payload) { events << [name, payload.slice(:method, :host, :exception)] }
    ActiveSupport::Notifications.subscribed(callback, 'request.http', &)
    events
  end

  def closed_port
    probe = TCPServer.new('127.0.0.1', 0)
    probe.addr[1].tap { probe.close }
  end

  it("announces one request.http per request, connecting included, with only the method and host") do
    response = nil

    events = announced { response = http_class.new('127.0.0.1', port).request(Net::HTTP::Get.new('/v2/snapshot?apiKey=secret')) }

    expect(response.body).to(eq('ok'))
    expect(events).to(eq([['request.http', { method: 'GET', host: '127.0.0.1' }]]))
  end

  it("announces one per request on a connection that's already open") do
    events = announced { http_class.new('127.0.0.1', port).start { |http| http.request(Net::HTTP::Get.new('/')) } }

    expect(events.size).to(eq(1))
  end

  it("announces a request that fails to connect, lets the error reach the caller, and announces the next one too") do
    http = http_class.new('127.0.0.1', closed_port)

    events = announced do
      2.times { expect { http.request(Net::HTTP::Get.new('/')) }.to(raise_error(Errno::ECONNREFUSED)) }
    end

    expect(events.map { |_, payload| payload[:exception]&.first }).to(eq(['Errno::ECONNREFUSED', 'Errno::ECONNREFUSED']))
  end

  it("gives the listener one http span per request, named without the path or query string") do
    listener = Datacat::TracingListener.new
    payload = { controller: 'StocksController', action: 'get_company_data', method: 'GET', path: '/stocks/AAPL/companydata' }

    ActiveSupport::Notifications.subscribed(listener, Datacat::TracingListener::PATTERN) do
      ActiveSupport::Notifications.instrument('process_action.action_controller', payload) do |event_payload|
        http_class.new('127.0.0.1', port).request(Net::HTTP::Get.new('/v3/reference/tickers/AAPL?apiKey=secret'))
        event_payload[:status] = 200
      end
    end

    row = Array.new(Datacat::TRACE_QUEUE.size) { Datacat::TRACE_QUEUE.pop }.sole
    expect(row[:spans].drop(1).map { |span| span.values_at(:name, :category, :parent) }).to(eq([['GET 127.0.0.1', 'http', 0]]))
    expect(row[:spans].to_json).not_to(include('apiKey', 'secret', '/v3'))
    expect(row[:http_ms]).to(be > 0)
  end
end
