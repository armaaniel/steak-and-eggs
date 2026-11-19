require 'rails_helper'
require 'socket'

RSpec.describe(Datacat::HttpEvents) do
  let(:http_class) { Net::HTTP }
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

  def announced(pattern = 'request.http', &)
    events = []
    callback = ->(name, _start, _finish, _id, payload) { events << [name, payload.slice(:method, :host, :exception)] }
    ActiveSupport::Notifications.subscribed(callback, pattern, &)
    events
  end

  def closed_port
    probe = TCPServer.new('127.0.0.1', 0)
    probe.addr[1].tap { probe.close }
  end

  def traced(&)
    listener = Datacat::TracingListener.new
    payload = { controller: 'StocksController', action: 'get_company_data', method: 'GET', path: '/stocks/AAPL/companydata' }

    ActiveSupport::Notifications.subscribed(listener, Datacat::TracingListener::PATTERN) do
      ActiveSupport::Notifications.instrument('process_action.action_controller', payload) do |event_payload|
        yield
        event_payload[:status] = 200
      end
    end

    Array.new(Datacat::TRACE_QUEUE.size) { Datacat::TRACE_QUEUE.pop }.sole
  end

  def http_spans(row)
    row[:spans].drop(1).map { |span| span.values_at(:name, :category, :parent) }
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

  it("is prepended to Net::HTTP exactly once, by the initializer") do
    expect(Net::HTTP.ancestors.count(Datacat::HttpEvents)).to(eq(1))
  end

  it("announces connect.http with only the host when a request opens its connection, and keeps connect private") do
    events = announced(/\A(request|connect)\.http\z/) { http_class.new('127.0.0.1', port).request(Net::HTTP::Get.new('/')) }

    expect(events).to(eq([['connect.http', { host: '127.0.0.1' }], ['request.http', { method: 'GET', host: '127.0.0.1' }]]))
    expect(http_class.private_method_defined?(:connect)).to(be(true))
  end

  it("records a refused connection on the connect and on the request around it") do
    events = announced(/\A(request|connect)\.http\z/) do
      expect { http_class.new('127.0.0.1', closed_port).request(Net::HTTP::Get.new('/')) }.to(raise_error(Errno::ECONNREFUSED))
    end

    expect(events.map { |name, payload| [name, payload[:exception]&.first] }).to(eq([['connect.http', 'Errno::ECONNREFUSED'], ['request.http', 'Errno::ECONNREFUSED']]))
  end

  it("gives the listener an http span per request with its connect inside, named without the path or query string") do
    row = traced { http_class.new('127.0.0.1', port).request(Net::HTTP::Get.new('/v3/reference/tickers/AAPL?apiKey=secret')) }

    expect(http_spans(row)).to(eq([['GET 127.0.0.1', 'http', 0], ['connect 127.0.0.1', 'http', 1]]))
    expect(row[:spans].to_json).not_to(include('apiKey', 'secret', '/v3'))
    expect(row[:http_ms]).to(be_within(0.01).of(row[:spans][1][:duration]))
  end

  it("shows net/http's retry after a read timeout as a second connect inside the same request") do
    silent = TCPServer.new('127.0.0.1', 0)
    responder = Thread.new do
      first = silent.accept
      while (line = first.gets) && line != "\r\n"; end
      second = silent.accept
      while (line = second.gets) && line != "\r\n"; end
      second.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
      second.close
      first.close
    end

    http = http_class.new('127.0.0.1', silent.addr[1])
    http.read_timeout = 0.2
    http.max_retries = 1
    response = nil
    row = traced { response = http.request(Net::HTTP::Get.new('/')) }

    expect(response.body).to(eq('ok'))
    expect(http_spans(row)).to(eq([['GET 127.0.0.1', 'http', 0], ['connect 127.0.0.1', 'http', 1], ['connect 127.0.0.1', 'http', 1]]))
  ensure
    responder&.kill
    silent&.close
  end
end
