class BackfillTraceErrorClassFromSpans < ActiveRecord::Migration[8.0]
  def up
    execute(<<~SQL)
      UPDATE traces SET error_class = (
        SELECT span.value->>'error_class'
        FROM json_each(traces.breakdown) AS span
        WHERE span.value->>'error_class' IS NOT NULL
        LIMIT 1)
      WHERE error_class IS NULL
        AND breakdown::text LIKE '%"error_class"%'
    SQL
  end

  def down
  end
end
