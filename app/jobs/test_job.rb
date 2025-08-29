class TestJob < ApplicationJob
 def perform(message = "Hello from TestJob!")
   puts "=" * 50
   puts "🚀 JOB EXECUTED AT: #{Time.current}"
   puts "📝 MESSAGE: #{message}"
   puts "🔄 JOB ID: #{job_id}" if respond_to?(:job_id)
   puts "=" * 50
   
   Rails.logger.info "=" * 50
   Rails.logger.info "🚀 JOB EXECUTED AT: #{Time.current}"
   Rails.logger.info "📝 MESSAGE: #{message}"
   Rails.logger.info "🔄 JOB ID: #{job_id}" if respond_to?(:job_id)
   Rails.logger.info "=" * 50
 end
end