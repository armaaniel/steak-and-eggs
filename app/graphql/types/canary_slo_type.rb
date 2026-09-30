module Types
  class CanarySloType < Types::BaseObject
    field(:target, Float, description: 'share of canary runs that must pass over the SLO period', null: false)
    field(:good, Integer, description: 'canary runs that passed in the range', null: false)
    field(:expected, Integer, description: 'canary runs the range should contain; missing runs count against the SLI', null: false)
    field(:period_good, Integer, description: 'canary runs that passed over the 30-day SLO period', null: false)
    field(:period_expected, Integer, description: 'canary runs the 30-day SLO period should contain', null: false)
    field(:budget_allowed, Integer, description: 'bad runs the SLO allows over its 30-day period', null: false)
    field(:budget_used, Integer, description: 'failed, unfinished and missing runs over the same 30 days', null: false)
  end
end
