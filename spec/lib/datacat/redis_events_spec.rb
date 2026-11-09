require 'rails_helper'

RSpec.describe(Datacat::RedisEvents) do
  let(:middleware) { Class.new(RedisClient::BasicMiddleware) { include Datacat::RedisEvents }.new(nil) }

  def announced(&)
    events = []
    callback = ->(name, _start, _finish, _id, payload) { events << [name, payload.slice(:command, :reply, :exception)] }
    ActiveSupport::Notifications.subscribed(callback, 'command.redis', &)
    events
  end

  it("announces each command as command.redis, with the command and its reply, and returns the reply") do
    reply = nil

    events = announced { reply = middleware.call(['get', 'price:AAPL'], nil) { '246.91' } }

    expect(reply).to(eq('246.91'))
    expect(events).to(eq([['command.redis', { command: ['get', 'price:AAPL'], reply: '246.91' }]]))
  end

  it("still announces a command that raises, with the error, and lets the error reach the caller") do
    events = announced do
      expect { middleware.call(['get', 'price:AAPL'], nil) { raise(RedisClient::ConnectionError, 'down') } }.to(raise_error(RedisClient::ConnectionError))
    end

    expect(events.sole.last).to(eq(command: ['get', 'price:AAPL'], exception: ['RedisClient::ConnectionError', 'down']))
  end
end
