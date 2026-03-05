# frozen_string_literal: true

require "test_helper"

class RateLimitErrorTest < ActiveSupport::TestCase
  test "stores reset_at" do
    err = RateLimitError.new("x", reset_at: 123)
    assert_equal 123, err.reset_at
  end

  test "default message" do
    err = RateLimitError.new
    assert_match(/rate limit/i, err.message)
  end
end
