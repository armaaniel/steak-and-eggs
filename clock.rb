require 'clockwork'
require_relative './config/environment'

include Clockwork

every(10.seconds, 'portfolio.updates') do
  PortfolioValuesWorker.perform_async
end