module Datacat
  module SqlShape
    STRING = /'(?:[^']|'')*'/
    COMMENT = %r{/\*.*?\*/}m
    NUMBER = /(?<![$\w])\d+(?:\.\d+)?(?:e[-+]?\d+)?\b/i

    def self.call(sql)
      shape = sql.gsub(STRING, '?').gsub(COMMENT, '').gsub(NUMBER, '?').squish
      shape unless shape.include?("'")
    end
  end
end
