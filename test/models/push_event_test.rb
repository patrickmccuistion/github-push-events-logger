# frozen_string_literal: true

require "test_helper"

class PushEventTest < ActiveSupport::TestCase
  test "push event has required attributes" do
    event = PushEvent.create!(
      event_id: "12345",
      repo_id: 1,
      actor_id: 2,
      ref: "refs/heads/main",
      head: "abc123",
      before: "def456"
    )
    assert_equal "12345", event.event_id
    assert_equal 1, event.repo_id
    assert_equal "refs/heads/main", event.ref
  end
end
