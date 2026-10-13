require 'rails_helper'
require 'rake'

RSpec.describe("cable_publish") do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("cable_publish") }

  describe("CableLoad.parse_stages") do
    it("keeps the default stages when none are given") do
      expect(CableLoad.parse_stages(nil)).to(eq(CableLoad::DEFAULT_STAGES))
      expect(CableLoad.parse_stages("")).to(eq(CableLoad::DEFAULT_STAGES))
    end

    it("reads interval and hold pairs from the environment format") do
      expect(CableLoad.parse_stages("250:180,222:180,200:60")).to(eq([[250, 180], [222, 180], [200, 60]]))
    end

    it("refuses a stage that is not two whole numbers") do
      expect { CableLoad.parse_stages("250:fast") }.to(raise_error(ArgumentError))
    end
  end
end
