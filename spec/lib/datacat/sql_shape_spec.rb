require 'rails_helper'

RSpec.describe(Datacat::SqlShape) do
  describe(".call") do
    it("replaces string and number values with ?") do
      sql = %q(SELECT 1 AS one FROM "users" WHERE LOWER("users"."username") = LOWER('armaan') AND "users"."id" != 42 LIMIT 1)

      expect(Datacat::SqlShape.call(sql)).to(eq('SELECT ? AS one FROM "users" WHERE LOWER("users"."username") = LOWER(?) AND "users"."id" != ? LIMIT ?'))
    end

    it("lets none of a buy's values through") do
      sql = %q(INSERT INTO "transactions" ("transaction_type", "value", "quantity", "created_at", "user_id", "symbol", "market_price") VALUES ('buy', 1234.56, 5, '2026-11-08 23:58:09.123456', 42, 'TSLA', 246.912) RETURNING "id")

      shape = Datacat::SqlShape.call(sql)

      expect(shape).to(eq('INSERT INTO "transactions" ("transaction_type", "value", "quantity", "created_at", "user_id", "symbol", "market_price") VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING "id"'))
      ['buy', '1234.56', '2026-11-08', '42', 'TSLA', '246.912'].each { |value| expect(shape).not_to(include(value)) }
    end

    it("removes Rails' query log comment, quotes and all") do
      sql = %q(SELECT "users".* FROM "users" WHERE "users"."id" = 42 LIMIT 1 /*application='SteakAndEggs',controller='stocks',action='buy'*/)

      expect(Datacat::SqlShape.call(sql)).to(eq('SELECT "users".* FROM "users" WHERE "users"."id" = ? LIMIT ?'))
    end

    it("keeps a value with a quote inside it whole") do
      expect(Datacat::SqlShape.call(%q(SELECT 1 FROM "users" WHERE "username" = 'o''brien'))).to(eq('SELECT ? FROM "users" WHERE "username" = ?'))
    end

    it("keeps a value that looks like a comment inside its quotes") do
      expect(Datacat::SqlShape.call(%q(SELECT 1 FROM "users" WHERE "username" = 'a/*b' AND "id" = 7 /*action='buy'*/))).to(eq('SELECT ? FROM "users" WHERE "username" = ? AND "id" = ?'))
    end

    it("replaces decimals, exponents and negative numbers") do
      expect(Datacat::SqlShape.call('UPDATE "users" SET "balance" = 1.5e-05, "x" = -3')).to(eq('UPDATE "users" SET "balance" = ?, "x" = -?'))
    end

    it("leaves digits inside names alone") do
      expect(Datacat::SqlShape.call('SAVEPOINT active_record_1')).to(eq('SAVEPOINT active_record_1'))
      expect(Datacat::SqlShape.call('SELECT "t0"."id" FROM "positions" "t0" WHERE "t0"."id" = $1')).to(eq('SELECT "t0"."id" FROM "positions" "t0" WHERE "t0"."id" = $1'))
    end

    it("gives up and returns nil when a quote is left unmatched") do
      expect(Datacat::SqlShape.call(%q(SELECT 1 FROM "users" WHERE "username" = 'armaan))).to(be_nil)
    end
  end
end
