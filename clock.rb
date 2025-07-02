require 'clockwork'
require_relative './config/environment'

include Clockwork

every(5.seconds, 'portfolio.updates') do
  PortfolioValuesWorker.perform_async
end