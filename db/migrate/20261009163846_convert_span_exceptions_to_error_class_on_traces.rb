class ConvertSpanExceptionsToErrorClassOnTraces < ActiveRecord::Migration[8.0]
  class Trace < ActiveRecord::Base
    self.table_name = 'traces'
  end

  def up
    Trace.where("breakdown::text LIKE '%\"exception\"%'").find_each do |trace|
      breakdown = trace.breakdown.transform_values do |span|
        next span unless span.is_a?(Hash) && span['exception'].is_a?(Array)
        span.except('exception').merge('error_class' => span['exception'].first)
      end
      trace.update_columns(breakdown: breakdown)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
