# frozen_string_literal: true

require "test_helper"
require "rake"

Rails.application.load_tasks

class DataRakeTest < ActiveSupport::TestCase
  setup do
    Rake::Task["data:prune_old_raw_events"]&.reenable
  end

  test "prune_old_raw_events removes events older than DAYS" do
    RawEvent.create!(id: "old1", payload: {}, created_at: 100.days.ago)
    RawEvent.create!(id: "old2", payload: {}, created_at: 95.days.ago)
    RawEvent.create!(id: "new1", payload: {}, created_at: 1.day.ago)

    ENV["DAYS"] = "90"
    Rake::Task["data:prune_old_raw_events"].invoke
    ENV.delete("DAYS")

    assert_not RawEvent.exists?("old1")
    assert_not RawEvent.exists?("old2")
    assert RawEvent.exists?("new1")
  end
end
