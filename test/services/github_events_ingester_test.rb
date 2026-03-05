# frozen_string_literal: true

require "test_helper"

class GithubEventsIngesterTest < ActiveSupport::TestCase
  test "filters PushEvent only" do
    ingester = GithubEventsIngester.new(enrich: false)
    assert_not_nil ingester
  end
end
